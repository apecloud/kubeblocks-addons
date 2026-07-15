#!/bin/sh
# Probe replication role from local MariaDB bootstrap state.
# Shebang is /bin/sh (not bash) because the kbagent sidecar image only ships
# busybox sh; when kbagent invokes the script via direct exec the kernel
# resolves the shebang, and /bin/bash ENOENT causes a silent exit=1 with empty
# output. Script body must remain POSIX-compatible.
# Return secondary if slave config exists, primary if no slave config.
# While bootstrap is still initializing, fail the probe instead of publishing a
# temporary role. KubeBlocks ignores failed roleProbe events, so pod labels are
# only updated after the local datadir state is stable.
#
# Role is determined by checking the master.info file:
#   - master.info exists  → CHANGE MASTER TO was run → secondary
#   - master.info missing → RESET SLAVE ALL was run (or never configured) → primary
#
# The local datadir state is authoritative for KubeBlocks pod role labels during
# bootstrap. syncerctl/DCS role can lag or be empty before HA lease convergence,
# which can transiently mark every pod secondary and empty the primary Service.
# Primary selection still stays file-based. Semisync primary publication also
# checks the local SQL listener and read_only state so a stale marker cannot keep
# a fenced old primary in the Primary Service.
#
# NOTE: KubeBlocks roleProbe exec runs in the kbagent execution context. The
# configured `container: mariadb` shares the target container's volume mounts,
# but the probe does not execute inside the mariadb container itself. Therefore
# the shared datadir markers are the authoritative truth once bootstrap is
# stable. For secondary publication we also require current local MariaDB
# reachability plus healthy replication truth so stale ready markers cannot keep
# or republish a broken replica.

data_dir() {
  printf "%s" "${MARIADB_DATADIR:-/var/lib/mysql}"
}

MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"
MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"

ready_file() {
  printf "%s/.replication-ready" "$(data_dir)"
}

sql_listener_ready_file() {
  printf "%s/.sql-listener-ready" "$(data_dir)"
}

pending_file() {
  printf "%s/.replication-pending" "$(data_dir)"
}

remote_root_fence_file() {
  printf "%s/.remote-root-fence-role" "$(data_dir)"
}

# alpha.80 v1 (Helen): the alpha.76 `switchover_fence_active_file` +
# `switchover_fence_active_is_fresh` + `SWITCHOVER_FENCE_MARKER_MAX_AGE_SECONDS`
# helpers are removed. alpha.79 v1 minimalist refactor in switchover.sh
# eliminated the marker writer (the pre-DCS fence chain was deleted), so
# this consumer-side check could never observe a fresh marker and always
# fell through to the existing role-marker logic. Pure dead-code cleanup,
# no runtime behavior change.

primary_read_write_ready_file() {
  printf "%s/.primary-read-write-ready" "$(data_dir)"
}

syncerctl_getrole() {
  local syncerctl_bin role
  syncerctl_bin="${SYNCERCTL_BIN:-/tools/syncerctl}"
  [ -x "${syncerctl_bin}" ] || return 1
  if command -v timeout >/dev/null 2>&1; then
    role=$(timeout 3 "${syncerctl_bin}" --host 127.0.0.1 --port "${SYNCERCTL_PORT:-3601}" getrole 2>/dev/null | tr -d '\r\n')
  else
    role=$("${syncerctl_bin}" --host 127.0.0.1 --port "${SYNCERCTL_PORT:-3601}" getrole 2>/dev/null | tr -d '\r\n')
  fi
  [ -n "${role}" ] || return 1
  printf "%s" "${role}"
}

master_info_file() {
  printf "%s/master.info" "$(data_dir)"
}

# alpha.106 v1 (Jack 2026-05-29): divergence_pending_file marker is written
# by fail_closed_for_gtid_divergence in cmpd-replication-merged.yaml and
# cmpd-semisync.yaml when the chart's startup-after-restart path detects a
# GTID divergence between local datadir and primary. The marker file is the
# fail-safe authority: while it is present, do not auto-heal. The reaper
# below explicitly bails when it sees this marker so the alpha.60 / Round
# 1c-B style orphan-event protection is preserved.
divergence_pending_file() {
  printf "%s/.replication-divergence-pending" "$(data_dir)"
}

# alpha.107 v1 (Jack 2026-05-29): mariadbd_listen_on_all_interfaces returns
# 0 iff mariadbd has at least one listening TCP socket bound to 0.0.0.0:3306
# (IPv4 wildcard) OR :::3306 (IPv6 wildcard). The check looks directly at
# /proc/net/tcp + /proc/net/tcp6 (kernel-truth) instead of `@@bind_address`
# (which can be set to "*" or "0.0.0.0" by config while a startup-time
# argument still pins the actual listening socket to 127.0.0.1). This is
# the alpha.102 v1 `.sql-listener-ready` marker semantic in its strongest
# form: the marker means "mariadbd is reachable from off-pod traffic past
# the bootstrap 127.0.0.1-only phase", and the only direct way to confirm
# that is to read the listen socket. Reaper Cond 7 (added in alpha.107)
# uses this so it never sets `.sql-listener-ready` while mariadbd is still
# bound to 127.0.0.1 (Round 1c-D async CM4 self-referential reaper bug,
# evidence sha d8d1aa42160c46df8eb0aecbdf41c739a9f691ece3724b05647c941fc7f75ac6).
#
# Port 3306 = hex 0CEA. Listen state in /proc/net/tcp{,6} = hex 0A.
# IPv4 0.0.0.0:3306 listen row local_address = "00000000:0CEA".
# IPv6 :::3306    listen row local_address = "00000000000000000000000000000000:0CEA".
# Function is POSIX-portable and uses awk + grep instead of `ss` so it
# works inside the kbagent action runtime that does not always ship `ss`.
mariadbd_listen_on_all_interfaces() {
  local tcp4 tcp6
  tcp4=$(awk 'NR>1 && $2=="00000000:0CEA" && $4=="0A" {print; exit}' /proc/net/tcp 2>/dev/null)
  if [ -n "${tcp4}" ]; then
    return 0
  fi
  tcp6=$(awk 'NR>1 && $2=="00000000000000000000000000000000:0CEA" && $4=="0A" {print; exit}' /proc/net/tcp6 2>/dev/null)
  if [ -n "${tcp6}" ]; then
    return 0
  fi
  return 1
}

# alpha.107 v1 (Jack 2026-05-29): reaper_audit_log writes a single line to
# `${dataMountPath}/log/reaper-audit.log`. The audit log is intentionally
# kept OUT of the `check_role()` `2>/dev/null` stderr-suppression path so a
# future investigation can reconstruct exactly which conditions the reaper
# observed and which steps it executed at every probe tick. Round 1c-D async
# CM4 narrow (2026-05-29 07:30-08:13) had to spend 40+ minutes reverse-
# engineering whether the reaper fired or not because the only fire-time
# signal was a single `echo >&2` that `check_role` then swallowed. This
# audit log makes the reaper's behavior self-documenting on disk. Format is
# `YYYY-MM-DDTHH:MM:SSZ reaper-audit kv=val kv=val ...`. The function is a
# best-effort write: if mkdir or tee fails we silently continue so the
# reaper's main logic does not depend on the audit log being functional.
reaper_audit_log() {
  local audit_dir audit_file ts
  audit_dir="$(data_dir)/log"
  audit_file="${audit_dir}/reaper-audit.log"
  mkdir -p "${audit_dir}" 2>/dev/null || return 0
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null)"
  printf '%s reaper-audit %s\n' "${ts}" "$*" >> "${audit_file}" 2>/dev/null || true
}

resolve_mariadb_cli() {
  if command -v mariadb >/dev/null 2>&1; then
    command -v mariadb
    return 0
  fi
  if [ -x "${MYSQL_CLIENT_DIR}/bin/mariadb" ]; then
    printf "%s" "${MYSQL_CLIENT_DIR}/bin/mariadb"
    return 0
  fi
  return 1
}

local_sql_as() {
  local user="$1"
  local mariadb_cli
  shift
  mariadb_cli=$(resolve_mariadb_cli) || return 1
  "${mariadb_cli}" "-u${user}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -N -s "$@" 2>/dev/null
}

local_sql() {
  local_sql_as "${MARIADB_ROOT_USER:-root}" "$@" || local_sql_as "${MARIADB_INTERNAL_ROOT_USER}" "$@"
}

local_sql_best_effort() {
  local_sql "$@" >/dev/null 2>&1 || true
}

sql_quote() {
  # Escape backslashes first, then single quotes (default sql_mode has no
  # NO_BACKSLASH_ESCAPES). Matches _helpers.tpl sql_value_literal.
  printf "%s" "$1" | sed -e 's/\\/\\\\/g' -e "s/'/''/g"
}

apply_remote_root_fence() {
  local role="$1"
  local user host password marker current sql
  host="${MARIADB_ROOT_HOST:-%}"
  case "${host}" in
    localhost|127.0.0.1|::1)
      return 0
      ;;
  esac

  # alpha.80 v1 (Helen): the alpha.76 `switchover_fence_active_is_fresh`
  # check has been removed. alpha.79 v1 minimalist deleted the marker
  # writer in switchover.sh, so this check could never observe a fresh
  # marker and always fell through. Pure dead-code cleanup, no runtime
  # behavior change.

  marker="$(remote_root_fence_file)"
  current="$(cat "${marker}" 2>/dev/null || true)"
  # The marker has one durable meaning: a secondary remote-root fence is
  # active.  A fully accepted primary is represented by marker absence; the
  # entrypoint clears it before publishing primary readiness and its runtime
  # reconciler requires it to stay absent.  Do not recreate a synthetic
  # "primary" fence on every roleProbe tick after that authoritative commit.
  if [ "${role}" = "primary" ] && [ ! -f "${marker}" ]; then
    return 0
  fi
  if [ "${role}" = "secondary" ] && [ "${current}" = "secondary" ]; then
    return 0
  fi

  user="$(sql_quote "${MARIADB_ROOT_USER:-root}")"
  host="$(sql_quote "${host}")"
  password="$(sql_quote "${MARIADB_ROOT_PASSWORD:-}")"
  if [ "${role}" = "secondary" ]; then
    # alpha.61 (Jack 01:40 review): user-facing root on secondary must NOT
    # carry SUPER / READ_ONLY ADMIN / BINLOG ADMIN / CONNECTION ADMIN, since
    # those bypass `@@global.read_only` and would re-introduce the alpha.59
    # false-PASS race when this pod is later promoted again. The legitimate
    # need for read_only-bypass on secondary (kb_health_check 1062 repair) is
    # served by `kb_internal_root` in `secondary_kb_health_check_repair_attempt`,
    # which keeps READ_ONLY ADMIN. SUPER is removed from this grant; the
    # best-effort `READ_ONLY ADMIN` and `CONNECTION ADMIN` for user-facing
    # root below are also removed (CONNECTION ADMIN is dropped by minimum-priv
    # principle without dependence on read_only-bypass behavior).
    # `REPLICATION MASTER ADMIN` is kept so the secondary can run
    # `CHANGE MASTER` / `START SLAVE` etc. for follow-time maintenance.
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
      GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO '${user}'@'${host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
  else
    # alpha.60: do NOT GRANT ALL PRIVILEGES because in MariaDB 10.11+ that
    # bundles READ_ONLY ADMIN / SUPER / BINLOG ADMIN, which let user-facing
    # root bypass @@global.read_only=ON. The post-DCS local-root fence in
    # switchover relies on read_only being effective for user-facing root,
    # so the primary-state grant must NOT include those bypass privileges.
    # GRANT OPTION is supplied via the trailing `WITH GRANT OPTION` clause,
    # not as a comma-separated privilege (which is a syntax error in some
    # MariaDB versions).
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
      GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER, CREATE USER ON *.* TO '${user}'@'${host}' WITH GRANT OPTION;
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
  fi

  if local_sql -e "${sql}" >/dev/null; then
    if [ "${role}" = "secondary" ]; then
      # alpha.61: only grant monitoring privileges that DO NOT bypass read_only.
      # READ_ONLY ADMIN and CONNECTION ADMIN are intentionally removed; the
      # 1062 repair path uses kb_internal_root (which retains READ_ONLY ADMIN
      # via its own grant chain) instead of relying on user-facing root having
      # bypass.
      local_sql_best_effort -e "SET SESSION sql_log_bin=0; GRANT BINLOG MONITOR ON *.* TO '${user}'@'${host}'; SET SESSION sql_log_bin=1;"
      local_sql_best_effort -e "SET SESSION sql_log_bin=0; GRANT SLAVE MONITOR ON *.* TO '${user}'@'${host}'; SET SESSION sql_log_bin=1;"
    fi
    if [ "${role}" = "secondary" ]; then
      printf "%s" "secondary" > "${marker}" 2>/dev/null || true
    else
      # Primary grants are now in place, so close the same marker contract the
      # entrypoint uses for a committed healthy primary.  Removal failure must
      # keep role publication fail-closed rather than hiding state drift.
      rm -f "${marker}" 2>/dev/null || return 1
    fi
    return 0
  fi
  # A failed primary transition must preserve an existing secondary fence so
  # the entrypoint can observe and repair it.  Secondary transition failures
  # retain the historical stale-marker cleanup behavior.
  if [ "${role}" != "primary" ]; then
    rm -f "${marker}" 2>/dev/null || true
  fi
  return 1
}

query_slave_status() {
  local mariadb_cli
  mariadb_cli=$(resolve_mariadb_cli) || return 1
  # SHOW SLAVE STATUS\G must keep field labels; local_sql intentionally uses
  # -N -s for scalar probes and collapses \G output into unlabeled values.
  "${mariadb_cli}" "-u${MARIADB_ROOT_USER:-root}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -e "SHOW SLAVE STATUS\\G" 2>/dev/null || \
    "${mariadb_cli}" "-u${MARIADB_INTERNAL_ROOT_USER}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
      -P3306 -h127.0.0.1 --connect-timeout=5 -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}

# Detect a slave SQL thread error caused by the addon's heartbeat table writing
# a duplicate-key (1062) or missing-table (1146) row that the new primary later
# replicates. We narrow strictly to that specific signature so the repair never
# fires on unrelated SQL errors. See addon-test-runner-write-after-bounded-role-gate
# guide and bootstrap-runner-preload-after-bounded-role-gate-case for context.
slave_status_has_kb_health_check_repairable_error() {
  local slave_status="$1"
  [ -n "${slave_status}" ] || return 1
  case ${slave_status} in
    *"Last_SQL_Errno: 1062"*) ;;
    *"Last_Errno: 1062"*) ;;
    *"Last_SQL_Errno: 1146"*) ;;
    *"Last_Errno: 1146"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"kubeblocks.kb_health_check"*) return 0 ;;
  esac
  return 1
}

# Best-effort repair invoked from the secondary roleProbe path when slave
# replication is broken specifically by the kb_health_check 1062/1146 signature.
# Always returns 0 so the probe can re-evaluate replication health afterwards;
# every attempt is logged with rc so closeout can observe whether repair fired.
#
# Critical post-Jack-19:45-review invariant: this function MUST NOT open
# `@@global.read_only` even briefly. The whole point of the secondary fence
# is to prove `double_writable=0` across the post-OpsRequest convergence
# window; flipping read_only OFF/ON for repair would create a small but real
# write window that contradicts the invariant we are testing for. We rely
# on `kb_internal_root` holding `READ_ONLY ADMIN` (granted by the addon's
# remote-root-fence path) so the maintenance DELETE works while
# `read_only=1` stays in place. If `kb_internal_root` cannot write for any
# reason, log rc and return; the next roleProbe tick re-evaluates.
#
# Idempotent: if the table is already empty the DELETE is a no-op (0 rows
# affected); if STOP/START SLAVE has already converged the next probe tick
# will observe IO/SQL=Yes and skip this branch entirely.
secondary_kb_health_check_repair_attempt() {
  local slave_status mariadb_cli rc
  slave_status=$(query_slave_status)
  slave_status_has_kb_health_check_repairable_error "${slave_status}" || return 0
  echo "secondary_kb_health_check_repair_attempt: detected 1062/1146 on kubeblocks.kb_health_check, attempting repair" >&2
  mariadb_cli=$(resolve_mariadb_cli) || {
    echo "secondary_kb_health_check_repair_attempt: rc=1 reason=no_mariadb_cli" >&2
    return 0
  }
  # Stop SQL thread so the repair DELETE is not racing the failing apply loop.
  # Uses kb_internal_root only; never user-facing root.
  "${mariadb_cli}" "-u${MARIADB_INTERNAL_ROOT_USER}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -N -s -e "STOP SLAVE SQL_THREAD;" >/dev/null 2>&1 || true
  # Narrow maintenance DELETE: only the kb_health_check rows. kb_internal_root
  # holds READ_ONLY ADMIN, so this writes through while @@global.read_only=1
  # stays untouched. sql_log_bin=0 keeps the DELETE from propagating (the new
  # primary already has the canonical state).
  "${mariadb_cli}" "-u${MARIADB_INTERNAL_ROOT_USER}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -N -s -e "
      SET SESSION sql_log_bin=0;
      CREATE DATABASE IF NOT EXISTS kubeblocks;
      CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check(type INT, check_ts BIGINT, PRIMARY KEY(type));
      DELETE FROM kubeblocks.kb_health_check;
      SET SESSION sql_log_bin=1;
    " >/dev/null 2>&1
  rc=$?
  "${mariadb_cli}" "-u${MARIADB_INTERNAL_ROOT_USER}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -N -s -e "START SLAVE SQL_THREAD;" >/dev/null 2>&1 || true
  echo "secondary_kb_health_check_repair_attempt: rc=${rc}" >&2
  return 0
}

not_ready() {
  printf '%s' "initializing"
  return 1
}

db_ready() {
  if [ "${MARIADB_ROLEPROBE_SKIP_DB_READY:-}" = "true" ]; then
    return 0
  fi
  local_sql -e "SELECT 1" >/dev/null
}

secondary_replication_ready() {
  # alpha.13 P2: rewrote pipeline-based grep checks to shell-builtin case pattern
  # matching to eliminate fork-on-each-check Pattern B zombie risk.
  # Pre-alpha.13 used 4× (printf | grep -q) → 8 forks per probe tick. When kbagent
  # SIGKILLs the script (timeoutSeconds <1s tail), orphan greps reparent to kbagent
  # (Go non-reaper) → zombie accumulation (~0.04%/probe @ 5s cadence in #402 redline).
  # Shell-builtin case has 0 child fork → no zombie residual under SIGKILL.
  local slave_status
  if [ "${MARIADB_ROLEPROBE_SKIP_DB_READY:-}" = "true" ]; then
    return 0
  fi
  slave_status=$(query_slave_status)
  [ -n "${slave_status}" ] || return 1
  case ${slave_status} in
    *"Slave_IO_Running: Yes"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"Slave_SQL_Running: Yes"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"Last_IO_Errno: 0"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"Last_SQL_Errno: 0"*) ;;
    *) return 1 ;;
  esac
}

primary_listener_ready() {
  local bind_line bind_address old_ifs
  [ "${MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY:-}" = "true" ] || return 0
  [ -f "$(sql_listener_ready_file)" ] || return 1
  if [ "${MARIADB_ROLEPROBE_SKIP_DB_READY:-}" = "true" ]; then
    return 0
  fi
  db_ready || return 1
  bind_line=$(local_sql -e "SHOW VARIABLES LIKE 'bind_address';" 2>/dev/null || true)
  [ -n "${bind_line}" ] || return 1
  old_ifs="${IFS}"
  # MariaDB returns "bind_address<TAB>value" with -N -s. Split on shell
  # whitespace so either tab or spaces from a mocked client work.
  IFS=" 	"
  set -- ${bind_line}
  IFS="${old_ifs}"
  bind_address="${2:-}"
  case "${bind_address}" in
    ""|127.*|localhost|::1)
      return 1
      ;;
  esac
}

primary_read_write_ready() {
  local read_only
  [ "${MARIADB_ROLEPROBE_REQUIRE_SQL_LISTENER_READY:-}" = "true" ] || return 0
  [ -f "$(primary_read_write_ready_file)" ] || return 1
  if [ "${MARIADB_ROLEPROBE_SKIP_DB_READY:-}" = "true" ]; then
    return 0
  fi
  read_only=$(local_sql -e "SELECT UPPER(CAST(@@global.read_only AS CHAR));" 2>/dev/null || true)
  case "${read_only}" in
    0|OFF)
      return 0
      ;;
  esac
  return 1
}

pending_secondary_fail_closed_ready() {
  local role read_only
  [ -f "$(master_info_file)" ] || return 1
  role=$(syncerctl_getrole) || return 1
  [ "${role}" = "secondary" ] || return 1
  db_ready || return 1
  read_only=$(local_sql -e "SELECT UPPER(CAST(@@global.read_only AS CHAR));" 2>/dev/null || true)
  case "${read_only}" in
    1|ON|NO_LOCK|NO_LOCK_NO_ADMIN) ;;
    *) return 1 ;;
  esac
  # alpha.10: r28 semisync VScale showed that read_only + semisync variable
  # shape is not enough to publish a secondary. A pod can hold
  # .replication-pending after a transient self-promotion/reset, have
  # syncerctl role=secondary, and still expose an empty SHOW SLAVE STATUS.
  # Role labels feed KB service routing and update ordering, so fail closed
  # until local SQL proves the replica IO/SQL threads are healthy.
  secondary_replication_ready || return 1
  semisync_secondary_shape_ready || return 1
  return 0
}

pending_primary_fail_closed_ready() {
  local role read_only
  [ ! -f "$(master_info_file)" ] || return 1
  role=$(syncerctl_getrole) || return 1
  [ "${role}" = "primary" ] || return 1
  db_ready || return 1
  read_only=$(local_sql -e "SELECT UPPER(CAST(@@global.read_only AS CHAR));" 2>/dev/null || true)
  case "${read_only}" in
    0|OFF) ;;
    *) return 1 ;;
  esac
  mariadbd_listen_on_all_interfaces || return 1
  semisync_primary_shape_ready || return 1
  return 0
}

semisync_primary_shape_ready() {
  local master_enabled slave_enabled
  [ "${MARIADB_REPLICATION_MODE:-}" = "semisync" ] || return 0
  master_enabled=$(local_sql -e "SELECT UPPER(CAST(@@global.rpl_semi_sync_master_enabled AS CHAR));" 2>/dev/null || true)
  slave_enabled=$(local_sql -e "SELECT UPPER(CAST(@@global.rpl_semi_sync_slave_enabled AS CHAR));" 2>/dev/null || true)
  case "${master_enabled}" in
    1|ON) ;;
    *) return 1 ;;
  esac
  case "${slave_enabled}" in
    0|OFF)
      return 0
      ;;
  esac
  return 1
}

semisync_secondary_shape_ready() {
  local master_enabled slave_enabled
  [ "${MARIADB_REPLICATION_MODE:-}" = "semisync" ] || return 0
  master_enabled=$(local_sql -e "SELECT UPPER(CAST(@@global.rpl_semi_sync_master_enabled AS CHAR));" 2>/dev/null || true)
  slave_enabled=$(local_sql -e "SELECT UPPER(CAST(@@global.rpl_semi_sync_slave_enabled AS CHAR));" 2>/dev/null || true)
  case "${master_enabled}" in
    0|OFF) ;;
    *) return 1 ;;
  esac
  case "${slave_enabled}" in
    1|ON)
      return 0
      ;;
  esac
  return 1
}

attempt_marker_self_heal() {
  # alpha.106 v1 (Jack 2026-05-29): defensive marker reaper for the
  # stuck-pending-after-recovery state surfaced by Round 1c-C async T6
  # Stop/Start (task442-full-n1-alpha105-r1c-fullrun-0617). When both pods
  # are stopped and started together, pod-0 startup probes pod-1:3306
  # before pod-1's mariadbd has finished accepting connections. The
  # cmpd-replication-merged.yaml alpha.92 bounded retry (default 60s) can
  # expire if pod-1 takes longer than that to come up; the startup script
  # then drops into block_existing_datadir_self_election_without_primary,
  # which writes `.replication-pending` and never returns to clear it.
  # After pod-1 becomes reachable, the slave IO/SQL threads catch up
  # cleanly but no actor (startup, HA syncer, switchover) ever flips the
  # markers back to ready, so roleProbe keeps publishing `initializing`
  # and the cluster never reaches Running. Live verification on
  # mdb-async-11076 confirmed that touching `.replication-ready` +
  # `.sql-listener-ready` and removing `.replication-pending` causes
  # roleProbe to immediately publish `secondary` and the cluster to
  # converge to Running (evidence sha
  # 154cb8735a4d5efe203303c36e779ed5b4617835571c4690313fb5a50a833b82).
  #
  # The reaper observes the live replication state and clears the pending
  # marker only when ALL strict conditions hold:
  #   1. .replication-pending exists
  #   2. .replication-divergence-pending does NOT exist (do not mask the
  #      alpha.60 / Round 1c-B style GTID divergence fail-closed)
  #   3. master.info exists (we are configured as a secondary; not in
  #      initial bootstrap or self-election path)
  #   4. .replication-ready may be present or absent. Older logic treated
  #      ready=present as "nothing to heal", but alpha.23 r75 C5 proved
  #      `.replication-pending` can be re-created after ready while SQL
  #      replication is already healthy; that mixed marker state still blocks
  #      HA follow forever and must be healed by clearing pending.
  #   5. db_ready (local MariaDB is up and accepting connections)
  #   6. secondary_replication_ready (Slave_IO_Running=Yes,
  #      Slave_SQL_Running=Yes, Last_IO_Errno=0, Last_SQL_Errno=0)
  #   7. mariadbd_listen_on_all_interfaces (added in alpha.107 — see below)
  # Any condition not met -> return 1 without touching markers. The
  # reaper never writes a binlog event and never calls admin SQL as
  # user-facing root: secondary_replication_ready already runs via the
  # internal admin path. Doc B Rule 4 (a) internal account / (b) no
  # binlog propagation / (c) only reads from existing tables / (d) does
  # not bypass the divergence-pending gate. Doc B Rule 6 (proposed by
  # Helen TL 2026-05-29 08:12): the reaper now verifies the marker
  # semantic invariant at write time (Cond 7 directly reads the kernel
  # listen socket) instead of inferring it from indirect health signals.
  # alpha.107 v1 (Jack 2026-05-29): Cond 7 closes the alpha.106 self-
  # referential reaper bug uncovered by Round 1c-D async CM4
  # (task442-full-n1-alpha106-r1d-fullrun-0712). After CM4 rolling restart,
  # the recreated pod-1 mariadbd was launched with `--bind-address=127.0.0.1`
  # (bootstrap-local-only phase). The PVC carried a stale master.info from
  # the previous incarnation, so the alpha.106 6-condition gate (pending /
  # divergence-pending absent / master.info present / ready absent /
  # db_ready / secondary_replication_ready) all passed at the next
  # roleProbe tick. The reaper touched `.replication-ready` +
  # `.sql-listener-ready` and removed `.replication-pending`. But
  # `.sql-listener-ready` carries the alpha.102 v1 semantic "mariadbd has
  # been re-bound to 0.0.0.0 past the bootstrap 127.0.0.1-only phase".
  # Pod-1's mariadbd was still 127.0.0.1-only, so the marker was a lie.
  # KB then promoted pod-1 to primary (saw ready=secondary in DCS, ran
  # switchover RESET SLAVE ALL + SET GLOBAL read_only=0) — but mariadbd
  # was still 127.0.0.1-only, so pod-0's slave IO got Connection refused.
  # Cluster never reached Running.
  #
  # Evidence sha256
  # d8d1aa42160c46df8eb0aecbdf41c739a9f691ece3724b05647c941fc7f75ac6.
  #
  # Cond 7 reads /proc/net/tcp + /proc/net/tcp6 directly and requires at
  # least one wildcard listen socket (0.0.0.0:3306 or :::3306) before
  # the reaper may set `.sql-listener-ready`. This is the strongest
  # possible direct proof of the marker's contract.
  reaper_audit_log "tick=enter"
  if [ ! -f "$(pending_file)" ]; then
    reaper_audit_log "cond=1 pending=absent rc=bail"
    return 1
  fi
  reaper_audit_log "cond=1 pending=present rc=continue"
  if [ -f "$(divergence_pending_file)" ]; then
    reaper_audit_log "cond=2 divergence_pending=present rc=bail"
    return 1
  fi
  reaper_audit_log "cond=2 divergence_pending=absent rc=continue"
  if [ ! -f "$(master_info_file)" ]; then
    reaper_audit_log "cond=3 master_info=absent rc=bail"
    return 1
  fi
  reaper_audit_log "cond=3 master_info=present rc=continue"
  if [ -f "$(ready_file)" ]; then
    reaper_audit_log "cond=4 ready=present rc=continue"
  else
    reaper_audit_log "cond=4 ready=absent rc=continue"
  fi
  if ! db_ready; then
    reaper_audit_log "cond=5 db_ready=false rc=bail"
    return 1
  fi
  reaper_audit_log "cond=5 db_ready=true rc=continue"
  if ! secondary_replication_ready; then
    reaper_audit_log "cond=6 secondary_replication_ready=false rc=bail"
    return 1
  fi
  reaper_audit_log "cond=6 secondary_replication_ready=true rc=continue"
  if ! mariadbd_listen_on_all_interfaces; then
    reaper_audit_log "cond=7 mariadbd_bind=127.0.0.1-only rc=bail"
    return 1
  fi
  reaper_audit_log "cond=7 mariadbd_bind=wildcard rc=continue"
  if ! touch "$(ready_file)"; then
    reaper_audit_log "fire step=touch_ready rc=fail"
    return 1
  fi
  reaper_audit_log "fire step=touch_ready rc=ok"
  if ! touch "$(sql_listener_ready_file)"; then
    reaper_audit_log "fire step=touch_sql_listener_ready rc=fail"
    return 1
  fi
  reaper_audit_log "fire step=touch_sql_listener_ready rc=ok"
  if ! rm -f "$(pending_file)"; then
    reaper_audit_log "fire step=rm_pending rc=fail"
    return 1
  fi
  reaper_audit_log "fire step=rm_pending rc=ok"
  reaper_audit_log "fire step=complete"
  echo "alpha.107 marker self-heal: replication ready confirmed via Slave_IO/SQL healthy + no divergence + mariadbd bound to 0.0.0.0; cleared .replication-pending and created .replication-ready + .sql-listener-ready" >&2
  return 0
}

check_role() {
  # alpha.106 v1 (Jack 2026-05-29): try to self-heal stuck-pending markers
  # before falling through to the existing pending/ready gate. The reaper
  # returns success only when the strict five-condition pre-check passes
  # (see attempt_marker_self_heal); otherwise it is a no-op and the
  # original logic stands. We swallow any unexpected runtime error so the
  # reaper never propagates a failure into the role-decision path.
  attempt_marker_self_heal 2>/dev/null || true

  # Before the startup command finishes role selection, do not publish a role.
  # Publishing "secondary" here causes secondary -> primary label flips for
  # pod-0, and publishing "primary" before the pending marker exists causes
  # primary -> secondary flips for later pods when syncer prestart is still
  # running.
  if [ -f "$(pending_file)" ] || [ ! -f "$(ready_file)" ]; then
    # If this pod already has persisted slave config and syncer/DCS reports it
    # as secondary, continuing to return a failed probe leaves any previous
    # primary label in place because KubeBlocks ignores failed roleProbe
    # outputs. Publishing secondary is safe only after local SQL proves the pod
    # is fail-closed read-only; replication may still be pending, but the pod
    # must not remain in the primary Service.
    if pending_primary_fail_closed_ready; then
      apply_remote_root_fence "primary" || { not_ready; return $?; }
      printf '%s' "primary"
      return 0
    fi
    if pending_secondary_fail_closed_ready; then
      apply_remote_root_fence "secondary" || { not_ready; return $?; }
      printf '%s' "secondary"
      return 0
    fi
    not_ready
    return $?
  fi

  # Check if slave config exists via master.info file:
  #   - CHANGE MASTER TO writes master.info
  #   - RESET SLAVE ALL deletes master.info
  if [ -f "$(master_info_file)" ]; then
    # Secondary publication needs more than a stale ready marker: if local
    # MariaDB is unreachable or SHOW SLAVE STATUS cannot prove healthy
    # replication, keep the pod unpublished until rejoin truth closes.
    db_ready || { not_ready; return $?; }
    if ! secondary_replication_ready; then
      # alpha.59: switchover action no longer waits for old-primary follow
      # convergence (kbagent enforces a 60s action ceiling). When the new
      # primary's replicated kb_health_check writes hit a duplicate-key on
      # this pod's stale row, repair narrowly and re-evaluate. Other SQL
      # errors are NOT swallowed: the next clause still fails not_ready.
      secondary_kb_health_check_repair_attempt
      secondary_replication_ready || { not_ready; return $?; }
    fi
    apply_remote_root_fence "secondary" || { not_ready; return $?; }
    printf '%s' "secondary"
  else
    primary_listener_ready || { not_ready; return $?; }
    primary_read_write_ready || { not_ready; return $?; }
    apply_remote_root_fence "primary" || { not_ready; return $?; }
    printf '%s' "primary"
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

check_role
