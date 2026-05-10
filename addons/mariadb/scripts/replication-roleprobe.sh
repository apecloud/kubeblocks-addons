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

primary_read_write_ready_file() {
  printf "%s/.primary-read-write-ready" "$(data_dir)"
}

master_info_file() {
  printf "%s/master.info" "$(data_dir)"
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
  printf "%s" "$1" | sed "s/'/''/g"
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

  marker="$(remote_root_fence_file)"
  current="$(cat "${marker}" 2>/dev/null || true)"
  if [ "${current}" = "${role}" ]; then
    return 0
  fi

  user="$(sql_quote "${MARIADB_ROOT_USER:-root}")"
  host="$(sql_quote "${host}")"
  password="$(sql_quote "${MARIADB_ROOT_PASSWORD:-}")"
  if [ "${role}" = "secondary" ]; then
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
      GRANT SELECT, PROCESS, RELOAD, SUPER, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO '${user}'@'${host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
  else
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      GRANT ALL PRIVILEGES ON *.* TO '${user}'@'${host}' WITH GRANT OPTION;
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
  fi

  if local_sql -e "${sql}" >/dev/null; then
    if [ "${role}" = "secondary" ]; then
      local_sql_best_effort -e "SET SESSION sql_log_bin=0; GRANT BINLOG MONITOR ON *.* TO '${user}'@'${host}'; SET SESSION sql_log_bin=1;"
      local_sql_best_effort -e "SET SESSION sql_log_bin=0; GRANT SLAVE MONITOR ON *.* TO '${user}'@'${host}'; SET SESSION sql_log_bin=1;"
      local_sql_best_effort -e "SET SESSION sql_log_bin=0; GRANT READ_ONLY ADMIN ON *.* TO '${user}'@'${host}'; SET SESSION sql_log_bin=1;"
      local_sql_best_effort -e "SET SESSION sql_log_bin=0; GRANT CONNECTION ADMIN ON *.* TO '${user}'@'${host}'; SET SESSION sql_log_bin=1;"
    fi
    printf "%s" "${role}" > "${marker}" 2>/dev/null || true
    return 0
  fi
  rm -f "${marker}" 2>/dev/null || true
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
  echo -n "initializing"
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

check_role() {
  # Before the startup command finishes role selection, do not publish a role.
  # Publishing "secondary" here causes secondary -> primary label flips for
  # pod-0, and publishing "primary" before the pending marker exists causes
  # primary -> secondary flips for later pods when syncer prestart is still
  # running.
  if [ -f "$(pending_file)" ] || [ ! -f "$(ready_file)" ]; then
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
    echo -n "secondary"
  else
    primary_listener_ready || { not_ready; return $?; }
    primary_read_write_ready || { not_ready; return $?; }
    apply_remote_root_fence "primary" || { not_ready; return $?; }
    echo -n "primary"
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

check_role
