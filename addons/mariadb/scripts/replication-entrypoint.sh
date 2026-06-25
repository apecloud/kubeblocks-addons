#!/bin/bash
# shellcheck disable=SC2034
DATA_DIR="${MARIADB_DATADIR:-/var/lib/mysql}"

mkdir -p ${DATA_DIR}/{log,binlog,tmp}
chown -R mysql:mysql ${DATA_DIR}
MYSQL_CLIENT_DIR=/tools/mysql-client
MARIADB_BIN="$(command -v mariadb)"
MARIADB_LOADER="$(ldd "${MARIADB_BIN}" | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\// && ($i ~ /ld-linux/ || $i ~ /ld-musl/)) { print $i; exit }}')"
mkdir -p "${MYSQL_CLIENT_DIR}/bin" "${MYSQL_CLIENT_DIR}/lib"
cp -L "${MARIADB_BIN}" "${MYSQL_CLIENT_DIR}/bin/mariadb.bin"
ldd "${MARIADB_BIN}" | awk '{for (i = 1; i <= NF; i++) if ($i ~ /^\//) print $i}' | sort -u | while IFS= read -r lib; do
  [ -n "${lib}" ] || continue
  cp -L "${lib}" "${MYSQL_CLIENT_DIR}/lib/"
done
cat > "${MYSQL_CLIENT_DIR}/bin/mariadb" <<EOF
#!/bin/sh
set -eu
ROOT="\$(CDPATH= cd -- "\$(dirname -- "\$0")"/.. && pwd)"
exec "\${ROOT}/lib/${MARIADB_LOADER##*/}" --library-path "\${ROOT}/lib" "\${ROOT}/bin/mariadb.bin" "\$@"
EOF
chmod 0555 "${MYSQL_CLIENT_DIR}/bin/mariadb"
# Set data dir group to kbagent's GID (1000) and grant group write so that
# kbagent can write switchover trigger files. Files inside remain mysql-owned.
chgrp 1000 ${DATA_DIR} && chmod g+w ${DATA_DIR}
# alpha.86 v1 (Helen 2026-05-19) — re-apply runtime-overrides
# layer permissions AFTER the `chown -R mysql:mysql` above,
# which would otherwise reset the gid=1000 + g+rwx set by
# init-syncer. Idempotent canonical rewrite of the loader
# file recovers from accidental edits / corruption from
# prior generations (Jack 07:03 peer review B2 follow-up).
# mariadbd's --defaults-extra-file silently accepts an
# empty `runtime-overrides.d/` so this block is also safe
# on fresh bootstrap.
mkdir -p ${DATA_DIR}/runtime-overrides.d
printf '!includedir %s/runtime-overrides.d/\n' "${DATA_DIR}" > ${DATA_DIR}/runtime-overrides.cnf
chgrp 1000 ${DATA_DIR}/runtime-overrides.d 2>/dev/null || true
chmod 0770 ${DATA_DIR}/runtime-overrides.d 2>/dev/null || true
chgrp 1000 ${DATA_DIR}/runtime-overrides.cnf 2>/dev/null || true
chmod 0660 ${DATA_DIR}/runtime-overrides.cnf 2>/dev/null || true
# alpha.89 v1 commit 13 v2 (Helen 2026-05-20, Jack
# post-commit-13-v1 install-time write-site requirement
# msg `696e7b16`) — seed runtime-overrides.d/ from
# `MARIADB_REPLICATION_MODE` BEFORE the first mariadbd
# process exec. Without this seeder the Helm value
# `replication.mode=semisync` set at install
# time would have no effect until the first
# reconfigureAction trigger; the seeder closes that gap
# so the chart-author-selected semisync/async state
# takes effect from the very first mariadbd start. The
# seeder writes byte-identical content to what
# reconfigureAction.persisted writes for the same env,
# so the two write-sites converge and a later reconfigure
# is a byte-equal no-op (mtime preserved by the cmp -s
# short-circuit). Empty env is a no-op (preserves
# behavior on clusters whose Helm values do not set the
# mode). Invalid mode fails the container (fail-closed):
# mariadbd does not start until the env is corrected.
# alpha.89 v1 commit 13 v3 (Helen 2026-05-20, Jack B3 fix
# msg `6e6eab69`) — when MARIADB_REPLICATION_MODE is
# non-empty the seeder script MUST be readable. The
# previous form `if [ -r ]; then ...; fi` silently skipped
# the seeder on a missing / unreadable script while leaving
# the env value set, so a non-empty mode could degrade to
# async (Class 1 silent fallback). Empty mode keeps the
# original lenient form because the seeder is a no-op
# anyway and a missing-script scenario is a deploy-time
# config drift that should still let async deployments
# boot.
if [ -n "${MARIADB_REPLICATION_MODE:-}" ]; then
  if [ ! -r /scripts/seed-replication-mode-overrides.sh ]; then
    echo "MARIADB_REPLICATION_MODE='${MARIADB_REPLICATION_MODE}' set but seeder script /scripts/seed-replication-mode-overrides.sh is missing or unreadable; refusing to start mariadbd (fail-closed) — fix the script mount and restart the pod" >&2
    exit 1
  fi
  seed_rc=0
  sh /scripts/seed-replication-mode-overrides.sh || seed_rc=$?
  if [ "${seed_rc}" -ne 0 ]; then
    echo "seed-replication-mode-overrides failed (rc=${seed_rc}); refusing to start mariadbd — correct MARIADB_REPLICATION_MODE and restart the pod" >&2
    exit 1
  fi
fi
# Signal to roleProbe that this pod is initializing — prevents spurious "primary"
# reports that would cause KubeBlocks to auto-trigger a switchover.
rm -f ${DATA_DIR}/.replication-ready
touch ${DATA_DIR}/.replication-pending

POD_INDEX="${POD_NAME##*-}"
SERVICE_ID=$((POD_INDEX + 1))
PRIMARY_HOST="${CLUSTER_NAME}-${COMPONENT_NAME}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN:-cluster.local}"
SOCK="/run/mysqld/mysqld.sock"
MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
# alpha.64 v1 (Jack 09:35 RED root cause + 10:01 v2 design ack):
# cmpd runtime sql-listener-fence GRANT statements MUST NOT introduce
# admin-bypass privileges (SUPER / READ_ONLY ADMIN / BINLOG ADMIN /
# CONNECTION ADMIN / REPLICATION SLAVE ADMIN / REPLICATION MASTER
# ADMIN / GRANT ALL PRIVILEGES) onto user-facing root, because those
# privileges bypass @@global.read_only=ON and let user-facing root
# write through fence intent. The previous wider grants leaked these
# privileges back to root@%/127.0.0.1/localhost between switchover-
# side fence and verifier read, producing the alpha.63 fresh-gatefix
# RED. The constants below are inlined non-bypass grant lists kept
# in sync with switchover.sh's SWITCHOVER_*_GRANT_BODY constants;
# ShellSpec strong-binds the alignment.
# alpha.81 v1: explicitly add SLAVE MONITOR to the grant bodies.
# Root cause: MariaDB 11.4 split legacy `REPLICATION CLIENT` into
# `BINLOG MONITOR` + `SLAVE MONITOR`. `GRANT REPLICATION CLIENT`
# only normalizes to `BINLOG MONITOR` in SHOW GRANTS — `SLAVE
# MONITOR` (required for `SHOW SLAVE STATUS`) is NOT included.
# Without `SLAVE MONITOR`, syncer engine's `IsSwitchoverDone()`
# in promotion_gate.go (which connects new primary -> old primary
# via `kb_internal_root@'%'` then issues `SHOW SLAVE STATUS`) gets
# ERROR 1227 ("need SLAVE MONITOR privilege"), returns false
# forever, the framework `HandlerSwitchoverForPrimary` cleanup
# gate never trips, and the DCS Switchover ConfigMap leaks. This
# broke same-cluster repeat switchover (the alpha.79 N=3 RED
# "there is another switchover unfinished" axis).
CMPD_EXPLICIT_PRIMARY_GRANT_BODY="SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT, SLAVE MONITOR, REPLICATION MASTER ADMIN, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER, CREATE USER"
CMPD_SECONDARY_FENCE_GRANT_BODY="SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, SLAVE MONITOR, REPLICATION MASTER ADMIN"
# alpha.108 P0a (Jack 2026-05-29): @localhost / @'127.0.0.1' variants
# restore BINLOG ADMIN to user-facing root @socket+loopback so the
# chart-internal `SET SESSION sql_log_bin=0; ...; SET SESSION
# sql_log_bin=1;` wrap mechanism in `set_local_root_account_state`
# / `set_remote_root_account_state` / `grant_optional_local_root_
# privileges` / `grant_optional_remote_root_privileges` actually
# takes effect. Background: from alpha.64 (security hardening to
# drop user-facing root admin-bypass) through alpha.107, the chart
# author's intended `sql_log_bin=0` wrap was structurally
# ineffective on ${LOCAL[@]} (= ROOT_LOCAL at bootstrap, user-
# facing root via socket) because user-facing root lost BINLOG
# ADMIN, so `SET SESSION sql_log_bin=0` returned ERROR 1227
# (Access denied; you need (at least one of) the BINLOG ADMIN
# privilege(s) for this operation) and `mariadb -e` silently
# continued to the subsequent CREATE USER / ALTER USER /
# REVOKE / GRANT / FLUSH PRIVILEGES statements WITH binlog
# enabled — each statement writing one binlog event with
# server_id=this_pod, accumulating as orphan events on the pod's
# local binlog. The bug was tracked indirectly through 5 alpha-
# test rounds (1c-A through 1c-E); Round 1c-E acceptance run
# finally surfaced the silent failure pattern directly via
# `grep "ERROR 1227" sql-listener-fence.log` (45 instances on
# frozen scene `mdb-async-11221`, sha
# 1d3554cd483bcf4eef9a96ce982b7341c6dce6a316f4e51b2731b1548f53b43f).
# Quantitative accounting: 45 silent-fail × ~5.5 DDL/fail ≈ 248
# orphan events matched the observed `gtid_binlog_pos` delta
# `2-2-248` (primary) vs `2-2-249` (pod-1 secondary) within 8%
# noise (FLUSH PRIVILEGES row-event variance + LOCK→LOCK same-
# state short-circuit + reconcile-repair mid-loop interruption).
#
# Security boundary preservation (per Helen TL 10:21 + Lily Doc B
# 主笔 10:20 alpha.64 hardening sub-boundary wording precision):
# BINLOG ADMIN is privilege-orthogonal to SUPER. SUPER allows
# `SET GLOBAL read_only=0` bypass and a broader admin-bypass set;
# BINLOG ADMIN allows ONLY `SET SESSION sql_log_bin=*` + a small
# set of binlog log-control statements; it does NOT bypass
# `@@global.read_only=1`. Restoring BINLOG ADMIN to user-facing
# root @'localhost' + @'127.0.0.1' therefore does NOT re-introduce
# the read_only bypass risk that alpha.64 hardening was designed
# to prevent. alpha.64 hardening boundary is preserved:
#   - user-facing root @'%' (remote): SUPER + BINLOG ADMIN +
#     READ_ONLY ADMIN remain dropped (unchanged from alpha.64)
#   - user-facing root @'localhost' + @'127.0.0.1' (socket /
#     loopback): SUPER + READ_ONLY ADMIN remain dropped; BINLOG
#     ADMIN restored to support chart-internal sql_log_bin=0 wrap
#
# Host-scope rationale: chart-internal SQL operations connect via
# unix socket or `127.0.0.1` loopback only (`${LOCAL[@]}` =
# `(mariadb ... -S "${SOCK}" ...)`). External users reaching the
# cluster via Service routing cannot reach the socket or
# loopback; @'%' remains the only attack surface for remote
# privilege escalation, and alpha.64 hardening on @'%' is intact.
CMPD_EXPLICIT_PRIMARY_GRANT_BODY_LOCAL="${CMPD_EXPLICIT_PRIMARY_GRANT_BODY}, BINLOG ADMIN"
CMPD_SECONDARY_FENCE_GRANT_BODY_LOCAL="${CMPD_SECONDARY_FENCE_GRANT_BODY}, BINLOG ADMIN"
# Best-effort monitor privileges (read-only). These never bypass
# read_only and are safe on user-facing root in any state. Tier A
# by Jack 10:05: failure here is allowed to log + continue.
#
# alpha.64 v3 (Jack 11:14 live-gate RED): the priv list contains
# MULTI-WORD tokens (BINLOG MONITOR / SLAVE MONITOR). This
# constant is documentation + ShellSpec strong-bind ONLY. DO NOT
# iterate via unquoted parameter expansion (`for x in
# ${CMPD_OPTIONAL_MONITOR_PRIVS}; do`) — POSIX `for` would split
# on IFS (whitespace) into 4 single-word tokens (BINLOG / MONITOR
# / SLAVE / MONITOR) and `GRANT BINLOG ON *.* ...` is invalid SQL,
# producing 1227 (insufficient priv: SLAVE MONITOR) on every
# `SHOW SLAVE STATUS` and breaking promote/demote. ALWAYS use the
# inline quoted list at callsites:
#   for privilege in "BINLOG MONITOR" "SLAVE MONITOR"; do ...; done
CMPD_OPTIONAL_MONITOR_PRIVS="BINLOG MONITOR SLAVE MONITOR"
# Fresh bootstrap keeps pod-0 as the deterministic first primary.
# Give its roleProbe/Endpoint publish path a bounded window before a
# later pod accepts a local syncer primary role.
SYNCER_PRIMARY_BOOTSTRAP_GRACE_SECONDS="${MARIADB_SYNCER_PRIMARY_BOOTSTRAP_GRACE_SECONDS:-45}"
SYNCER_PRIMARY_BOOTSTRAP_GRACE_UNTIL="$(($(date +%s) + SYNCER_PRIMARY_BOOTSTRAP_GRACE_SECONDS))"
# alpha.80 v1 (Helen): the alpha.76 `switchover_fence_active_is_fresh`
# function + `SWITCHOVER_FENCE_MARKER_MAX_AGE_SECONDS` env are
# removed. alpha.79 v1 minimalist deleted the marker writer in
# switchover.sh, so this consumer-side function never observed a
# fresh marker; the consumer checks in `reconcile_sql_listener_for_
# syncer_primary_once` and `set_remote_root_account_state` always
# fell through. Pure dead-code cleanup, no runtime behavior change.
ROOT_LOCAL=(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -S "${SOCK}" -N -s)
INTERNAL_LOCAL=(mariadb "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -S "${SOCK}" -N -s)
LOCAL=("${ROOT_LOCAL[@]}")
LIFECYCLE_MARKER="/tmp/.mariadb-startup-lifecycle"
if [ ! -f "${LIFECYCLE_MARKER}" ]; then
  touch "${LIFECYCLE_MARKER}" 2>/dev/null || true
  if [ -f "${DATA_DIR}/.prestop-fence-started" ] || \
     [ -f "${DATA_DIR}/.prestop-fence-complete" ] || \
     [ -f "${DATA_DIR}/.prestop-fence-failed" ]; then
    mkdir -p ${DATA_DIR}/log 2>/dev/null || true
    {
      printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
      printf 'decision=clear-stale-prestop-fence-on-container-start\n'
      printf 'reason=tmp lifecycle marker absent; this is the first startup attempt in this container\n'
      printf '\n'
    } >> ${DATA_DIR}/log/startup-fence.log 2>/dev/null || true
  fi
  # alpha.12 (r35 T15): preStop can kill mariadbd after a primary
  # reconcile has written .sql-listener-ready, then kbagent starts
  # a fresh bootstrap-local-only mariadbd on 127.0.0.1. Those
  # publish markers describe the old process, not the new one.
  # Clear them together with the stale preStop fence so startup
  # must re-prove listener exposure and role readiness.
  rm -f ${DATA_DIR}/.prestop-fence-started \
    ${DATA_DIR}/.prestop-fence-complete \
    ${DATA_DIR}/.prestop-fence-failed \
    ${DATA_DIR}/.prestop-fence-watchdog-active \
    ${DATA_DIR}/.sql-listener-ready \
    ${DATA_DIR}/.primary-read-write-ready \
    ${DATA_DIR}/.replication-ready
elif [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  {
    printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
    printf 'decision=refuse-restart-after-prestop\n'
    printf 'reason=prestop-fence-started marker exists in this container lifecycle\n'
    printf '\n'
  } >> ${DATA_DIR}/log/startup-fence.log 2>/dev/null || true
  rm -f ${DATA_DIR}/.replication-ready
  touch ${DATA_DIR}/.replication-pending
  echo "preStop fence marker exists; refusing to restart mariadbd in terminating pod"
  while true; do
    sleep 3600
  done
fi
HAS_EXISTING_DATA=false
if [ -d "${DATA_DIR}/mysql" ] || \
   ls ${DATA_DIR}/binlog/*.bin* >/dev/null 2>&1; then
  HAS_EXISTING_DATA=true
fi
read_only_value() {
  "${LOCAL[@]}" -e "SELECT UPPER(CAST(@@global.read_only AS CHAR));" 2>/dev/null \
    | tr -d '\r' \
    | awk 'NF {print $1; exit}'
}
read_only_is_fail_closed() {
  local value
  value="$(read_only_value || true)"
  case "${value}" in
    1|ON|NO_LOCK|NO_LOCK_NO_ADMIN)
      return 0
      ;;
  esac
  return 1
}
set_fail_closed_read_only() {
  local label="${1:-fail-closed}"
  if "${LOCAL[@]}" -e "SET GLOBAL read_only = NO_LOCK_NO_ADMIN;" 2>/dev/null && read_only_is_fail_closed; then
    echo "Set fail-closed read_only=NO_LOCK_NO_ADMIN (${label})"
    return 0
  fi
  if "${LOCAL[@]}" -e "SET GLOBAL read_only = ON;" 2>/dev/null && read_only_is_fail_closed; then
    echo "Set fail-closed read_only=ON (${label})"
    return 0
  fi
  if "${LOCAL[@]}" -e "SET GLOBAL read_only = 1;" 2>/dev/null && read_only_is_fail_closed; then
    echo "Set fail-closed read_only fallback=1 (${label})"
    return 0
  fi
  echo "WARNING: read_only still OFF after fail-closed attempts (${label})"
  echo "WARNING: failed to set fail-closed read_only (${label})"
  return 1
}
set_replica_read_only() {
  # alpha.64 v2 (Jack 10:32 HOLD blocker 1): Tier B required LOCK
  # failures MUST propagate rc to caller. set_replica_read_only is
  # called from publish_replica_after_rejoin_ready, runtime-secondary
  # reconcile, and configure_replication_from_primary_service_once;
  # any failure here means the replica's read_only/lock state is
  # not what we promised, so the caller must NOT publish
  # ready/role. set_fail_closed_read_only also already returns 1
  # on its own failure mode.
  local label="${1:-replica-read-only}" syncer_primary_rc
  replica_lock_abort_if_syncer_primary "${label}-before-lock"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  rm -f ${DATA_DIR}/.primary-read-write-ready
  local rc=0
  lock_remote_root_writes "${label}" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-after-remote-lock"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  set_fail_closed_read_only "${label}" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-after-read-only"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  lock_local_root_writes "${label}" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-after-local-lock"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  ensure_semisync_replica_role "${label}" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-after-semisync-shape"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  if [ "${rc}" -ne 0 ]; then
    prestop_watchdog_log "set-replica-read-only label=${label} rc=1 tier=required fail_closed=true"
    return 1
  fi
}
primary_local_root_write_ready() {
  # alpha.70 v1: replace shell SQL probe with syncerctl writecheck.
  # alpha.71 v1: bounded retry around syncerctl writecheck so a
  # syncer-internal startup race (dbManager not yet connected to
  # mariadbd at chart bootstrap T+15s) self-recovers within budget.
  #
  # Before alpha.70, this function ran the kb_health_check INSERT
  # through ROOT_LOCAL (the cluster's user-facing root). ROOT_LOCAL
  # is intentionally locked to the read-replication-admin-only-no-
  # bypass priv set (no BINLOG ADMIN). The probe started its first
  # statement with `SET SESSION sql_log_bin=0;` which requires
  # BINLOG ADMIN -> always failed with ERROR 1227 (42000), causing
  # the chart watchdog to never write `.sql-listener-ready` and
  # roleProbe to stay in `initializing` indefinitely. Evidence in
  # alpha.69 v1 5.D-r2 RED: every line of
  # /var/lib/mysql/log/sql-listener-fence.log was the same 1227.
  #
  # alpha.70 v1 replaced the shell SQL probe with `syncerctl
  # writecheck`, which delegates the probe to syncer engine's
  # Manager.WriteCheck (operations/replica/writecheck.go calling
  # engines/mariadb/manager.go). The syncer holds its own DB
  # connection (built from MARIADB_INTERNAL_ROOT credentials,
  # which retain full bypass priv), so the probe succeeds without
  # asking ROOT_LOCAL to do anything beyond its locked-down priv
  # set. /tools/syncerctl is already installed by the init-syncer
  # initContainer (see template line 92, also used by
  # syncerctl_pause and syncerctl_getrole below).
  #
  # alpha.70 v1 5.D-r3 N=1 RED surfaced the next-layer race: the
  # chart bootstrap calls this function ~15s after mariadbd start,
  # but syncer's engine `dbManager.IsDBStartupReady()` (called by
  # the WriteCheck.PreCheck path) returns false until syncer's own
  # *sql.DB has connected to mariadbd and completed its startup
  # readiness ping. A single attempt fails with
  # `ERR_PRECHECK_FAILED: database is not ready` and the chart
  # marks `sql-listener-primary-expose-failed` permanently.
  # Direct evidence: pod-0
  # /var/lib/mysql/log/sql-listener-fence.log was 116 bytes (one
  # error), HA loop continued spinning 8+ minutes but chart
  # bootstrap never re-invoked the function.
  #
  # alpha.71 v1 fix: bounded retry, max_attempts attempts with
  # sleep_seconds between each. rc-only contract - syncerctl exit
  # code is the only control-flow signal; stdout/stderr (including
  # ERR_PRECHECK_FAILED text and any 503 / curl / JSON errors)
  # are appended to sql-listener-fence.log for postmortem only,
  # never parsed. Marker files (.replication-ready /
  # .sql-listener-ready / .primary-read-write-ready) are NOT
  # touched here; they remain caller-managed in set_primary_read_
  # write() after ALL gates pass. Each attempt checks
  # .prestop-fence-started first so termination interrupts the
  # retry budget immediately; total budget is
  # max_attempts * sleep_seconds = 30s, well under
  # terminationGracePeriodSeconds=120.
  local label="${1:-primary-local-root-write-ready}"
  if [ ! -x /tools/syncerctl ]; then
    prestop_watchdog_log "primary-local-root-write-ready label=${label} rc=1 reason=syncerctl-not-available"
    return 1
  fi
  local max_attempts=30
  local sleep_seconds=1
  local attempt=1
  while [ "${attempt}" -le "${max_attempts}" ]; do
    if [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
      prestop_watchdog_log "primary-local-root-write-ready label=${label} rc=1 via=syncerctl-writecheck reason=prestop-fence-started attempt=${attempt}"
      return 1
    fi
    if /tools/syncerctl --host 127.0.0.1 --port 3601 writecheck \
      >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
      prestop_watchdog_log "primary-local-root-write-ready label=${label} rc=0 via=syncerctl-writecheck attempt=${attempt}"
      return 0
    fi
    prestop_watchdog_log "primary-local-root-write-ready label=${label} rc=1 via=syncerctl-writecheck attempt=${attempt}/${max_attempts}"
    if [ "${attempt}" -lt "${max_attempts}" ]; then
      sleep "${sleep_seconds}"
    fi
    attempt=$((attempt + 1))
  done
  prestop_watchdog_log "primary-local-root-write-ready label=${label} rc=1 via=syncerctl-writecheck reason=budget-exhausted attempts=${max_attempts}"
  return 1
}
primary_internal_root_write_ready() {
  # alpha.99 (Helen 2026-05-25): write probe uses addon-owned
  # kubeblocks.kb_addon_write_probe scratch table, NOT
  # kubeblocks.kb_health_check. kb_health_check is owned by
  # syncer (engines/mariadb/manager.go WriteCheck / GetOpTimestamp);
  # addon scripts touching it violates the ownership boundary and
  # caused the 1032 cascade documented in iron-evidence repro
  # (cluster mdb-repro-1032 2026-05-25 08:03Z). Probe upserts a
  # single row keyed on a fixed probe_id; no DELETE, because the
  # next probe just overwrites via ON DUPLICATE KEY UPDATE.
  # sql_log_bin=0 keeps the probe local-only (the syncerctl
  # writecheck path is the cluster-wide write verification).
  local label="${1:-primary-internal-root-write-ready}"
  if "${INTERNAL_LOCAL[@]}" -e "
    SET SESSION sql_log_bin=0;
    CREATE DATABASE IF NOT EXISTS kubeblocks;
    CREATE TABLE IF NOT EXISTS kubeblocks.kb_addon_write_probe(probe_id VARCHAR(64) PRIMARY KEY, ts BIGINT);
    INSERT INTO kubeblocks.kb_addon_write_probe(probe_id, ts)
      VALUES ('internal-root', UNIX_TIMESTAMP())
      ON DUPLICATE KEY UPDATE ts=VALUES(ts);
    SET SESSION sql_log_bin=1;
  " >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
    prestop_watchdog_log "primary-internal-root-write-ready label=${label} rc=0"
    return 0
  fi
  prestop_watchdog_log "primary-internal-root-write-ready label=${label} rc=1"
  return 1
}
primary_write_gates_ready() {
  # alpha.110 P0a URGENT Direction E (Jack 15:26 + Helen TL 15:34 sealed +
  # Edward 15:51 + Rocco 15:53 + Lily 15:54 4-cosign LGTM):
  # Skip primary_local_root_write_ready syncerctl-writecheck step on
  # reconcile-repair-begin path. Root cause: chart-side
  # reconcile_sql_listener_for_syncer_primary_once fires
  # `runtime-primary-listener-reconcile-repair-begin` every ~3s while
  # syncer-role=primary but chart markers OUT-OF-SYNC; each iteration's
  # writecheck INSERTs into kb_health_check generating 1 binlog event
  # per fire → cumulative orphan events on local domain → post-
  # reconfigure switchover GTID divergence → alpha.60 fail-closed →
  # HA permanent refuse follow → cluster stuck Updating. Round 1c-G
  # 2nd mdb-async-10271 saw 18 events accumulate in 2.5min loop fire
  # window.
  #
  # alpha.110 P0a URGENT Direction E preserves alpha.99 Helen
  # 2026-05-25 design intent (syncer's WriteCheck deliberately writes
  # to binlog for replication health verification): happy-path
  # writecheck still runs on normal primary promotion paths (line
  # 1942/2134/2218/2383 callers use labels without "-no-writecheck"
  # suffix). Only the reconcile-repair-begin path passes label with
  # "-no-writecheck" suffix (per Rocco 15:53 stricter suffix-anchored
  # pattern), triggering this case to skip the writecheck step while
  # preserving primary_internal_root_write_ready (kb_addon_write_probe
  # addon-owned + explicit SET sql_log_bin=0 per line 596-602 — NOT
  # orphan event source) + marker emit + role probe + read_only +
  # role transition logic in set_primary_read_write happy path.
  local label="${1:-primary-write-gates-ready}"
  case "${label}" in
    *-no-writecheck)
      prestop_watchdog_log "primary-write-gates-ready label=${label} reason=skip-writecheck-repair-path"
      primary_internal_root_write_ready "${label}" || return 1
      return 0
      ;;
  esac
  primary_local_root_write_ready "${label}" || return 1
  primary_internal_root_write_ready "${label}" || return 1
}
fail_primary_read_write_gate() {
  local label="$1"
  local reason="$2"
  rm -f ${DATA_DIR}/.primary-read-write-ready
  # tier=fail-path-defensive: this is the failure handler for an
  # already-failed primary write gate; defensive locking is
  # best-effort observability. The caller has already concluded
  # the gate failed and is not about to publish ready/role.
  lock_remote_root_writes "${label}-${reason}" || true # tier=fail-path-defensive
  set_fail_closed_read_only "${label}-${reason}" || true # tier=fail-path-defensive
  lock_local_root_writes "${label}-${reason}" || true # tier=fail-path-defensive
  prestop_watchdog_log "primary-read-write ${reason} rc=1"
}
set_primary_read_write() {
  # alpha.110 P0a URGENT Direction E (Jack 15:26 + 4-cosign sealed):
  # accept label parameter so callers can pass "-no-writecheck" suffix
  # through to primary_write_gates_ready for repair-path skip.
  # Default label preserves alpha.109 and earlier behavior.
  local label="${1:-primary-read-write}"
  if [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
    prestop_watchdog_log "skip-primary-read-write reason=prestop-fence-started"
    mark_replication_pending
    return 1
  fi
  if ! unlock_local_root_writes "${label}"; then
    rm -f ${DATA_DIR}/.primary-read-write-ready
    prestop_watchdog_log "primary-read-write local-root-unlock rc=1 label=${label}"
    return 1
  fi
  if ! unlock_remote_root_writes "${label}"; then
    fail_primary_read_write_gate "${label}" "remote-root-unlock"
    return 1
  fi
  if "${LOCAL[@]}" -e "SET GLOBAL read_only = 0;" 2>/dev/null; then
    if ! primary_write_gates_ready "${label}"; then
      fail_primary_read_write_gate "${label}" "write-gate"
      return 1
    fi
    rm -f ${DATA_DIR}/.remote-root-fence-role
    touch ${DATA_DIR}/.primary-read-write-ready
    prestop_watchdog_log "primary-read-write rc=0 label=${label}"
    return 0
  fi
  if "${LOCAL[@]}" -e "SET GLOBAL read_only = 'OFF';" 2>/dev/null; then
    if ! primary_write_gates_ready "${label}"; then
      fail_primary_read_write_gate "${label}" "write-gate"
      return 1
    fi
    rm -f ${DATA_DIR}/.remote-root-fence-role
    touch ${DATA_DIR}/.primary-read-write-ready
    prestop_watchdog_log "primary-read-write rc=0 label=${label}"
    return 0
  fi
  fail_primary_read_write_gate "${label}" "read-only-open"
  prestop_watchdog_log "primary-read-write rc=1 label=${label}"
  return 1
}
mark_replication_pending() {
  rm -f ${DATA_DIR}/.replication-ready
  rm -f ${DATA_DIR}/.primary-read-write-ready
  # DO NOT clear .sql-listener-ready here. That marker represents
  # "mariadbd has been re-bound to 0.0.0.0 (past the bootstrap
  # 127.0.0.1-only phase)" — a per-process state, not a
  # replication-ready state. Clearing it during a runtime role
  # transition causes the next reconcile_sql_listener_for_syncer_
  # primary_once tick to take the bootstrap "fresh start" branch
  # in expose_sql_listener_for_primary_role and physically restart
  # mariadbd, which kills the syncer lease and triggers the
  # demoted peer to re-acquire leader and write orphan events.
  # Bind-state is only reset by the bootstrap start_mariadbd_process
  # at line 1901 (a fresh container restart will rebuild it).
  rm -f ${DATA_DIR}/.remote-root-fence-role
  touch ${DATA_DIR}/.replication-pending
}
mark_replication_ready() {
  touch ${DATA_DIR}/.replication-ready
  touch ${DATA_DIR}/.sql-listener-ready
  rm -f ${DATA_DIR}/.replication-pending ${DATA_DIR}/.replication-divergence-pending
}
mark_replication_divergence_pending() {
  mark_replication_pending
  touch ${DATA_DIR}/.replication-divergence-pending
}
replica_lock_abort_if_syncer_primary() {
  local label="${1:-replica-lock}" role
  role="$(query_local_syncer_role || true)"
  if [ "${role}" = "primary" ]; then
    prestop_watchdog_log "replica-lock-abort-on-dcs-primary label=${label} reason=dcs_promoted_during_replica_lock"
    return 2
  fi
  return 0
}
accept_syncer_primary_promotion_from_replica_path() {
  local label="${1:-replica-path}" role
  role="$(query_local_syncer_role || true)"
  [ "${role}" = "primary" ] || return 1
  prestop_watchdog_log "replica-path-accept-dcs-primary label=${label} action=accept-primary-promotion"
  if expose_sql_listener_for_primary_role "syncer-primary-during-${label}"; then
    mark_replication_ready
    return 0
  fi
  return 2
}
gtid_state_is_covered_by() {
  local local_state="$1"
  local primary_state="$2"
  local token ptoken domain server seq pdom pserver pseq found
  [ -z "${local_state}" ] && return 0
  IFS=',' read -r -a local_tokens <<< "${local_state}"
  IFS=',' read -r -a primary_tokens <<< "${primary_state}"
  for token in "${local_tokens[@]}"; do
    token="${token//[[:space:]]/}"
    [ -n "${token}" ] || continue
    IFS='-' read -r domain server seq <<< "${token}"
    [ -n "${domain}" ] && [ -n "${server}" ] && [ -n "${seq}" ] || return 1
    found=false
    for ptoken in "${primary_tokens[@]}"; do
      ptoken="${ptoken//[[:space:]]/}"
      [ -n "${ptoken}" ] || continue
      IFS='-' read -r pdom pserver pseq <<< "${ptoken}"
      if [ "${pdom}" = "${domain}" ] && [ "${pserver}" = "${server}" ]; then
        if [ "${pseq}" -ge "${seq}" ] 2>/dev/null; then
          found=true
          break
        fi
        return 1
      fi
    done
    [ "${found}" = "true" ] || return 1
  done
  return 0
}
persist_gtid_divergence_evidence() {
  local branch="$1" local_state="$2" primary_state="$3" slave_status="$4"
  local evidence_file="${DATA_DIR}/log/replication-divergence.log"
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  {
    printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf 'branch=%s\n' "${branch}"
    printf 'decision=divergence-pending\n'
    printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
    printf 'primary_host=%s\n' "${PRIMARY_HOST:-unknown}"
    printf 'service_id=%s\n' "${SERVICE_ID:-unknown}"
    printf 'has_existing_data=%s\n' "${HAS_EXISTING_DATA:-unknown}"
    printf 'local_gtid_binlog_state=%s\n' "${local_state:-<empty>}"
    printf 'primary_gtid_binlog_state=%s\n' "${primary_state:-<empty>}"
    printf 'slave_status_begin\n'
    if [ -n "${slave_status}" ]; then
      printf '%s\n' "${slave_status}"
    else
      printf '<empty>\n'
    fi
    printf 'slave_status_end\n'
    printf '\n'
  } >> "${evidence_file}" 2>/dev/null || true
}
block_existing_datadir_self_election_without_primary() {
  # tier=fail-path-defensive: this branch is reached only when
  # primary is unreachable and existing datadir cannot self-elect;
  # the function deliberately does NOT publish ready/role and
  # returns 0 to make the caller exit. Defensive locking is
  # best-effort observability (Tier A class).
  local local_state slave_status evidence_file
  [ "${HAS_EXISTING_DATA}" = "true" ] || return 1
  local_state=$("${LOCAL[@]}" -e "SELECT @@global.gtid_binlog_state;" 2>/dev/null || echo "")
  slave_status=$("${LOCAL[@]}" -e "SHOW SLAVE STATUS;" 2>/dev/null || true)
  "${LOCAL[@]}" -e "STOP SLAVE;" 2>/dev/null || true
  lock_remote_root_writes "no-primary-existing-datadir" || true # tier=fail-path-defensive
  set_fail_closed_read_only "no-primary-existing-datadir" || true # tier=fail-path-defensive
  mark_replication_pending
  lock_local_root_writes "no-primary-existing-datadir" || true # tier=fail-path-defensive
  evidence_file="${DATA_DIR}/log/replication-no-primary-pending.log"
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  {
    printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    printf 'decision=no-primary-pending\n'
    printf 'pod_name=%s\n' "${POD_NAME:-unknown}"
    printf 'service_id=%s\n' "${SERVICE_ID:-unknown}"
    printf 'has_existing_data=%s\n' "${HAS_EXISTING_DATA:-unknown}"
    printf 'local_gtid_binlog_state=%s\n' "${local_state:-<empty>}"
    printf 'slave_status_begin\n'
    if [ -n "${slave_status}" ]; then
      printf '%s\n' "${slave_status}"
    else
      printf '<empty>\n'
    fi
    printf 'slave_status_end\n'
    printf '\n'
  } >> "${evidence_file}" 2>/dev/null || true
  echo "Existing datadir with stale slave config but no primary found. Keeping read_only and replication pending instead of self-electing."
  return 0
}
fail_closed_for_gtid_divergence() {
  local primary_state local_state slave_status
  [ "${HAS_EXISTING_DATA}" = "true" ] || return 1
  local_state=$("${LOCAL[@]}" -e "SELECT @@global.gtid_binlog_state;" 2>/dev/null)
  [ -n "${local_state}" ] || return 1
  primary_state=$(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@global.gtid_binlog_state;" 2>/dev/null || echo "")
  [ -n "${primary_state}" ] || return 1
  if gtid_state_is_covered_by "${local_state}" "${primary_state}"; then
    return 1
  fi
  slave_status=$("${LOCAL[@]}" -e "SHOW SLAVE STATUS;" 2>/dev/null || true)
  "${LOCAL[@]}" -e "STOP SLAVE;" 2>/dev/null || true
  # tier=fail-path-defensive: divergence has already been detected;
  # function returns 0 only after marking pending and never publishes
  # ready/role. Defensive locks are best-effort observability.
  lock_remote_root_writes "gtid-divergence" || true # tier=fail-path-defensive
  set_fail_closed_read_only "gtid-divergence" || true # tier=fail-path-defensive
  mark_replication_divergence_pending
  lock_local_root_writes "gtid-divergence" || true # tier=fail-path-defensive
  persist_gtid_divergence_evidence "fail_closed_for_gtid_divergence" "${local_state}" "${primary_state}" "${slave_status}"
  echo "GTID divergence detected for existing datadir rejoin: local binlog state ${local_state}, primary binlog state ${primary_state}. Keeping replication pending for rebuild/resync."
  return 0
}
prestop_watchdog_log() {
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  printf '%s prestop-watchdog %s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" "$*" \
    >> ${DATA_DIR}/log/prestop-watchdog.log 2>/dev/null || true
}
sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}
grant_internal_admin_runtime_privileges() {
  # alpha.109 P0a (Jack 12:08 Round 1c-F FAIL § 5.3 halt + Helen 12:13/12:17/12:19
  # TL pick NEW C+probe combo + Rocco 12:18 INTERNAL_LOCAL self-query syntax +
  # Edward 12:19 Doc B Rule 6 cross-link + Lily 12:21 cosign): close the
  # chicken-and-egg residual that Round 1c-F surfaced as production-FATAL on
  # CM secondary-restart bootstrap.
  #
  # The grant loop below uses ROOT_LOCAL (root@localhost) as the SQL session
  # to GRANT admin privileges to kb_internal_root. At bootstrap-time, before
  # the role-decision branches run set_local_root_account_state (which
  # alpha.108 P0a B2 restored BINLOG ADMIN to root@localhost via host-scoped
  # _LOCAL grant body), root@localhost does NOT yet have BINLOG ADMIN. The
  # multi-statement wrapper `SET SESSION sql_log_bin=0; GRANT ...; SET
  # SESSION sql_log_bin=1` therefore silently fails on the SET (ERROR 1227),
  # the GRANT runs WITH binlog enabled, and 14 DDL events (2 host × 7 privilege)
  # leak into the local binlog. On a fresh-create primary that's
  # tolerable because the secondary follows from primary's GTID position and
  # inherits those events. On a CM secondary-restart with persistent PVC
  # (kb_internal_root already has the privileges from a prior bootstrap),
  # the leak is pure waste: 14 events emitted with this pod's server_id
  # that the primary does NOT have, producing GTID divergence → alpha.60
  # fail-closed marker `.replication-divergence-pending` → HA permanent
  # follow rejection → role probe timeout → Cluster Failed. This is the
  # exact mechanism Round 1c-F mdb-async-12851 hit on CM4 post-rolling-restart
  # (pod-0 secondary, ERROR 1227 leak 9s post-restart, divergence-pending
  # marker emitted, cluster Failed in 22min).
  #
  # alpha.109 P0a closes this via two-source-of-truth defense-in-depth:
  # (1) Fast-path sentinel file `.bootstrap-complete` from prior successful
  #     bootstrap. Read via single stat() — no SQL roundtrip.
  # (2) SQL probe fallback via INTERNAL_LOCAL identity self-query
  #     `SHOW GRANTS FOR CURRENT_USER()` substring match for ALL PRIVILEGES
  #     or BINLOG ADMIN. Rocco 12:18 picked INTERNAL_LOCAL self-query
  #     (not ROOT_LOCAL cross-user SHOW GRANTS) to avoid the symmetric
  #     ERROR 1142 silent-fail trap that ROOT_LOCAL's possible missing
  #     SELECT on mysql.global_priv would induce; INTERNAL_LOCAL self-query
  #     is always allowed for self regardless of mysql DB privilege.
  # Either path → skip the grant loop and touch the sentinel for future
  # fast-path. Neither path → run the grant loop (initial bootstrap path,
  # acceptable leak on fresh-create) and touch the sentinel after.
  #
  # Edward 12:19 cross-link: alpha.105 fence verifier rewrite (Round 1c-C)
  # established the "verifier MUST NOT self-fall-victim to the same family
  # trap" pattern; INTERNAL_LOCAL self-query is the alpha.109 P0a application
  # of that pattern at the probe layer.
  local label="${1:-internal-local-admin-runtime-privileges}"
  local sentinel="${DATA_DIR}/.bootstrap-complete"

  # Fast-path: sentinel from prior successful bootstrap
  if [ -f "${sentinel}" ]; then
    prestop_watchdog_log "internal-local-admin-runtime-privilege-skip label=${label} reason=sentinel"
    return 0
  fi

  # Defense-in-depth: SQL probe via INTERNAL_LOCAL identity self-query
  # (Rocco 12:18 INTERNAL_LOCAL self-query, NOT ROOT_LOCAL cross-user query —
  # avoids ERROR 1142 family silent-fail trap; Edward 12:19 Rule 6 verifier
  # self-immunity application).
  if "${INTERNAL_LOCAL[@]}" -BNe "SELECT 1" >/dev/null 2>&1 \
     && "${INTERNAL_LOCAL[@]}" -BNe "SHOW GRANTS FOR CURRENT_USER()" 2>/dev/null \
          | grep -qiE "(ALL PRIVILEGES|BINLOG[[:space:]]*ADMIN)"; then
    touch "${sentinel}" 2>/dev/null || true
    prestop_watchdog_log "internal-local-admin-runtime-privilege-skip label=${label} reason=sql-probe"
    return 0
  fi

  # Initial bootstrap path (kb_internal_root not yet granted admin privileges).
  # The 14-event leak in this path is acceptable on fresh-create because the
  # secondary follows from primary's GTID position which includes the leak
  # (mutual bootstrap state, Rocco 10:39 sealed). The leak does NOT recur on
  # secondary-restart because the sentinel/probe fast-paths above will skip.
  local user host privilege sql
  user="$(sql_quote "${MARIADB_INTERNAL_ROOT_USER}")"
  for host in localhost 127.0.0.1; do
    for privilege in "REPLICATION SLAVE ADMIN" "REPLICATION MASTER ADMIN" "BINLOG ADMIN" "BINLOG MONITOR" "SLAVE MONITOR" "CONNECTION ADMIN" "READ_ONLY ADMIN"; do
      sql="
        SET SESSION sql_log_bin=0;
        GRANT ${privilege} ON *.* TO '${user}'@'${host}';
        FLUSH PRIVILEGES;
        SET SESSION sql_log_bin=1;
      "
      if "${ROOT_LOCAL[@]}" -e "${sql}" >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
        prestop_watchdog_log "internal-local-admin-runtime-privilege privilege=${privilege} label=${label} host=${host} via=root rc=0"
        continue
      fi
      if "${INTERNAL_LOCAL[@]}" -e "${sql}" >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
        prestop_watchdog_log "internal-local-admin-runtime-privilege privilege=${privilege} label=${label} host=${host} via=internal rc=0"
        continue
      fi
      prestop_watchdog_log "internal-local-admin-runtime-privilege privilege=${privilege} label=${label} host=${host} rc=1"
    done
  done
  touch "${sentinel}" 2>/dev/null || true
}
ensure_internal_local_admin() {
  # alpha.66 v1 (Jack 12:18 alpha.65 v2 install/script live-gate
  # RED + Jack 12:34 alpha.66 v1 design HOLD + Jack 12:39 design
  # ACCEPT with 3 tightening): the existing local @localhost +
  # @127.0.0.1 paths preserve full admin-priv kb_internal_root
  # for syncer's local AdminDB connection (127.0.0.1:3306 match
  # priority falls on @127.0.0.1 first because it is the most
  # specific host). The new @'%' record below is detection-only:
  # it is required so syncer's `IsAdminCreated()` (which queries
  # `mysql.user WHERE host='%' AND user LIKE 'kb%'`) can detect
  # the admin user and trigger `mgr.DB = mgr.AdminDB` in
  # IsRunning(). The @'%' record carries `ACCOUNT LOCK` AND zero
  # privileges, so it cannot be used for any remote auth (LOCK
  # rejects auth) and cannot run any SQL even if LOCK is somehow
  # bypassed (no GRANT). This preserves the alpha.64 v1 fence
  # spirit: user-facing root has no admin bypass; internal admin
  # remains effectively local-only at runtime.
  #
  # alpha.67 v1 (Jack 12:56 alpha.66 v1 package-level review HOLD):
  # the @'%' "zero privileges" contract was only declarative in
  # alpha.66 v1 — `CREATE USER IF NOT EXISTS` does NOT clear an
  # existing account's privileges, and `ACCOUNT LOCK` does not
  # revoke. If `kb_internal_root@'%'` happens to pre-exist (e.g.
  # from a misconfigured prior install or upgrade) with grants,
  # alpha.66 v1 would lock the account but leave the privileges
  # intact, violating the security contract. alpha.67 v1 inserts
  # an explicit `REVOKE ALL PRIVILEGES, GRANT OPTION FROM` step
  # between `CREATE USER ... @'%'` and `ALTER USER ... @'%'
  # ACCOUNT LOCK` so the zero-privilege state is enforced at the
  # write site, not just declared. This pattern matches the
  # alpha.64 v1 LOCK paths (set_local/remote_root_account_state
  # LOCK and lock_local_root_for_prestop) which already use the
  # same REVOKE statement before re-applying the non-bypass grant
  # body.
  #
  # alpha.68 v2 (Jack 15:39 alpha.67 v1 live-gate RED + 15:45
  # alpha.68 v1 design HOLD + 15:58 alpha.68 v2 Direction B
  # ACCEPT with refined checkpoint #3): the alpha.67 v1
  # detection-only LOCKED+zero-priv `@'%'` design was correct
  # for the IsAdminCreated host='%' detection requirement but
  # broke cross-member syncer auth. syncer's `GetMemberConnection`
  # uses `config.GetDBConnWithAddr(addr)` with `AdminUsername`
  # (= kb_internal_root via MYSQL_ADMIN_USER) for cross-pod TCP,
  # which authenticates via the @'%' record. LOCKED → 4151
  # Access denied; secondary cannot poll leader health; cluster
  # stays in RoleProbeNotDone forever (1064 errors / 30s in
  # bounded gate).
  #
  # SQL matrix audit (Helen 15:53 + Jack 15:58 design ACCEPT)
  # established the cross-member exact grant requirement:
  #   - IsReadonly (slave.go): SELECT @@global.* — USAGE
  #   - IsMemberLagging / ReadCheck (manager.go) — SELECT on
  #     kubeblocks.kb_health_check
  #   - IsMemberHealthy leader-only WriteCheck — INSERT/UPDATE on
  #     kubeblocks.kb_health_check (CREATE fallback handled by
  #     primary_local_root_write_ready local bootstrap; cross-
  #     pod path does not need CREATE because leader has pre-
  #     created table during local primary bootstrap before role
  #     publish)
  #   - setSemiSyncSourceTimeout (semi_sync.go), Follow secondary
  #     -> leader path — REPLICATION MASTER ADMIN required
  #     because `SET GLOBAL rpl_semi_sync_master_timeout = N`
  #     is an admin-bypass write on the target leader's mariadbd
  #
  # alpha.68 v2 grant contract (exact allowlist):
  #   * REPLICATION CLIENT ON *.* (SHOW SLAVE/MASTER STATUS)
  #   * REPLICATION MASTER ADMIN ON *.* (SET GLOBAL
  #     rpl_semi_sync_master_timeout)
  #   * SELECT, INSERT, UPDATE ON kubeblocks.kb_health_check
  #     (ReadCheck + WriteCheck)
  #
  # Refined checkpoint #3 (Jack 15:58): no NEW net capability,
  # no read_only-bypass class. `REPLICATION MASTER ADMIN` is
  # already in alpha.64 v1 `CMPD_EXPLICIT_PRIMARY_GRANT_BODY`
  # which user-facing `root@'%'` carries; root and
  # `kb_internal_root` share `MARIADB_ROOT_PASSWORD`, so an
  # attacker with the password and remote access already has
  # this capability via root@'%'. Net attack-surface delta = 0
  # for `REPLICATION MASTER ADMIN`.
  #
  # Still forbidden on `kb_internal_root@'%'`: ALL PRIVILEGES /
  # SUPER / READ_ONLY ADMIN / CONNECTION ADMIN / BINLOG ADMIN /
  # REPLICATION SLAVE ADMIN / DELETE / DROP / CREATE USER /
  # schema-wide DML / CREATE on kubeblocks.* (table is pre-
  # created by primary_local_root_write_ready).
  #
  # alpha.69 v1 (Jack 17:57 alpha.68 v2 install/script live-gate
  # RED 3-evidence-chains closeout + 18:20 alpha.69 v1 design
  # ACCEPT with runtime-acceptance tightening): the alpha.68 v2
  # @'%' grant contract above was correct, but
  # ensure_internal_local_admin had a bootstrap precondition
  # gap. alpha.68 v2's `GRANT SELECT, INSERT, UPDATE ON
  # kubeblocks.kb_health_check TO 'kb_internal_root'@'%'`
  # assumed the table existed, but the function is called
  # from `wait_for_internal_local_admin
  # "startup-before-role-decision"` which runs BEFORE the
  # role-decision branches that invoke
  # primary_local_root_write_ready (the function that creates
  # `kubeblocks.kb_health_check`). On a fresh boot the table
  # therefore does not exist when the @'%' GRANT runs, the
  # GRANT fails with Error 1146, ensure_internal_local_admin
  # returns rc=1, wait_for_internal_local_admin loops forever,
  # role decision never reaches expose_sql_listener_for_*_role,
  # mariadbd stays bound to 127.0.0.1, and cross-pod TCP
  # connections see Error 2002.
  #
  # alpha.69 v1 changes:
  #   - Add CREATE DATABASE IF NOT EXISTS kubeblocks BEFORE the
  #     @'%' grant block (idempotent; ROOT_LOCAL via socket has
  #     GRANT ALL PRIVILEGES locally so can CREATE).
  #   - Add CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check
  #     same area (idempotent). primary_local_root_write_ready
  #     and primary_internal_root_write_ready still run later
  #     post-role-decision — both are idempotent on the table.
  #   - Add GRANT SELECT ON mysql.user TO 'kb_internal_root'@'%'
  #     AFTER the existing three @'%' grants. syncer's connection
  #     URL (engines/mysql/config.go line 71) includes `/mysql`
  #     as the default database, so go-sql-driver issues
  #     `init_db = mysql` during the handshake. alpha.68 v2
  #     grants on @'%' are global (REPLICATION CLIENT +
  #     REPLICATION MASTER ADMIN ON *.*) + table-specific on
  #     kubeblocks.kb_health_check; the cross-pod init_db
  #     handshake fails with Error 1044 because the @'%'
  #     account has no privilege on the `mysql` schema. SELECT
  #     ON mysql.user is the narrow table-specific privilege
  #     that satisfies the init_db check.
  #
  # Net attack-surface delta = 0 for SELECT ON mysql.user vs
  # root@'%' (alpha.64 v1 CMPD_EXPLICIT_PRIMARY_GRANT_BODY
  # grants `SELECT ON *.*` to root@'%'; root and
  # kb_internal_root share MARIADB_ROOT_PASSWORD).
  #
  # MariaDB 11.4 SHOW GRANTS normalization (Jack 18:20
  # tightening): `GRANT REPLICATION CLIENT ON *.*` is the
  # backward-compatible source syntax; SHOW GRANTS displays
  # the normalized form `BINLOG MONITOR ON *.*` (MariaDB 11.4
  # split REPLICATION CLIENT into BINLOG MONITOR + SLAVE
  # MONITOR). `BINLOG MONITOR` in SHOW GRANTS output is the
  # **positive** normalized form of our `REPLICATION CLIENT`
  # grant and is allowed; runtime grant verification uses
  # semantic-equivalent matching. This is DIFFERENT from
  # `BINLOG ADMIN`, which remains in the **forbidden** admin-
  # bypass list and must NOT appear on `kb_internal_root@'%'`.
  # Source-side ShellSpec checks the literal source SQL
  # (`GRANT REPLICATION CLIENT`); runtime live-gate acceptance
  # uses the normalized form (`BINLOG MONITOR`). These two
  # are different write-side vs read-side口径; ShellSpec
  # literal-match logic must not be reused to validate runtime
  # SHOW GRANTS output (Jack 18:24 reminder).
  #
  # alpha.70+ mandatory blocking debt (was alpha.69 in earlier
  # planning, renamed because chart-only alpha.69 ships
  # alongside as bounded short-term unblock): syncer source
  # change so cross-member `GetDBConnWithAddr` uses a dedicated
  # lower-priv credential AND removes `/mysql` from the
  # connection DSN (or syncer-side mechanism replaces direct
  # cross-pod admin SQL such as setSemiSyncSourceTimeout).
  # alpha.70+ goal state restores `kb_internal_root@'%'` to
  # alpha.67 v1 LOCKED + zero-priv (clean security boundary).
  # alpha.69 v1 is bounded short-term unblock, NOT a final
  # design.
  local label="${1:-internal-local-admin}"
  local user password sql replication_user
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  user="$(sql_quote "${MARIADB_INTERNAL_ROOT_USER}")"
  password="$(sql_quote "${MARIADB_ROOT_PASSWORD}")"
  # alpha.72 v1 (Jack XP review HOLD blocker #2/#8 — `5a7c68e5`):
  # use shell var for replication user so env / SQL / member-join
  # / inline CHANGE MASTER 全部 reference the same value (no env
  # absent → empty MASTER_USER risk). Default to "kb_replicator"
  # if MARIADB_REPL_USER env missing.
  replication_user="$(sql_quote "${MARIADB_REPL_USER:-kb_replicator}")"
  # alpha.72 v1 wording per Jack #3: MariaDB DDL/GRANT statements
  # are NOT atomic; if a single statement fails mid-block the
  # already-applied statements remain. The SET sql_log_bin=0
  # bracketing only prevents binlog propagation. We rely on
  # idempotent convergence (CREATE IF NOT EXISTS + ALTER UNLOCK +
  # REVOKE ALL + GRANT specific) so subsequent retries can finish
  # any partial state.
  sql="
    SET SESSION sql_log_bin=0;
    CREATE USER IF NOT EXISTS '${user}'@'localhost' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'localhost' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'localhost' ACCOUNT UNLOCK;
    GRANT ALL PRIVILEGES ON *.* TO '${user}'@'localhost' WITH GRANT OPTION;
    CREATE USER IF NOT EXISTS '${user}'@'127.0.0.1' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'127.0.0.1' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'127.0.0.1' ACCOUNT UNLOCK;
    GRANT ALL PRIVILEGES ON *.* TO '${user}'@'127.0.0.1' WITH GRANT OPTION;
    CREATE DATABASE IF NOT EXISTS kubeblocks;
    CREATE TABLE IF NOT EXISTS kubeblocks.kb_post_dcs_fence_probe(probe_id VARCHAR(64) PRIMARY KEY, ts BIGINT);
    CREATE TABLE IF NOT EXISTS kubeblocks.kb_addon_write_probe(probe_id VARCHAR(64) PRIMARY KEY, ts BIGINT);
    CREATE USER IF NOT EXISTS '${user}'@'%' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'%' ACCOUNT UNLOCK;
    REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'%';
    GRANT RELOAD, PROCESS ON *.* TO '${user}'@'%';
    GRANT REPLICATION CLIENT ON *.* TO '${user}'@'%';
    GRANT SLAVE MONITOR ON *.* TO '${user}'@'%';
    GRANT REPLICATION MASTER ADMIN ON *.* TO '${user}'@'%';
    GRANT SELECT, INSERT, UPDATE ON kubeblocks.* TO '${user}'@'%';
    GRANT SELECT ON mysql.user TO '${user}'@'%';
    CREATE USER IF NOT EXISTS '${replication_user}'@'%' IDENTIFIED BY '${password}';
    ALTER USER '${replication_user}'@'%' IDENTIFIED BY '${password}';
    ALTER USER '${replication_user}'@'%' ACCOUNT UNLOCK;
    REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${replication_user}'@'%';
    GRANT REPLICATION SLAVE ON *.* TO '${replication_user}'@'%';
    FLUSH PRIVILEGES;
    SET SESSION sql_log_bin=1;
  "
  if "${ROOT_LOCAL[@]}" -e "${sql}" >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
    grant_internal_admin_runtime_privileges "${label}"
    prestop_watchdog_log "internal-local-admin label=${label} via=root rc=0"
    return 0
  fi
  if "${INTERNAL_LOCAL[@]}" -e "${sql}" >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
    grant_internal_admin_runtime_privileges "${label}"
    prestop_watchdog_log "internal-local-admin label=${label} via=internal rc=0"
    return 0
  fi
  prestop_watchdog_log "internal-local-admin label=${label} rc=1"
  return 1
}
probe_internal_local_admin() {
  if "${INTERNAL_LOCAL[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
    return 0
  fi
  prestop_watchdog_log "internal-local-admin-probe rc=1"
  return 1
}
internal_local_admin_has_required_privileges() {
  local semisync_master_value semisync_slave_value read_only_value
  semisync_master_value=$("${INTERNAL_LOCAL[@]}" -e "SELECT @@global.rpl_semi_sync_master_enabled;" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
  case "${semisync_master_value}" in
    ON|on)
      semisync_master_value=1
      ;;
    OFF|off)
      semisync_master_value=0
      ;;
    0|1)
      ;;
    *)
      prestop_watchdog_log "internal-local-admin-required-privilege privilege=REPLICATION_MASTER_ADMIN probe=read-semisync-value rc=1 value=${semisync_master_value:-<empty>}"
      return 1
      ;;
  esac
  if "${INTERNAL_LOCAL[@]}" -e "SET GLOBAL rpl_semi_sync_master_enabled=${semisync_master_value};" >/dev/null 2>&1; then
    prestop_watchdog_log "internal-local-admin-required-privilege privilege=REPLICATION_MASTER_ADMIN probe=set-semisync-same-value rc=0"
  else
    prestop_watchdog_log "internal-local-admin-required-privilege privilege=REPLICATION_MASTER_ADMIN probe=set-semisync-same-value rc=1"
    return 1
  fi
  semisync_slave_value=$("${INTERNAL_LOCAL[@]}" -e "SELECT @@global.rpl_semi_sync_slave_enabled;" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
  case "${semisync_slave_value}" in
    ON|on)
      semisync_slave_value=1
      ;;
    OFF|off)
      semisync_slave_value=0
      ;;
    0|1)
      ;;
    *)
      prestop_watchdog_log "internal-local-admin-required-privilege privilege=REPLICATION_SLAVE_ADMIN probe=read-semisync-value rc=1 value=${semisync_slave_value:-<empty>}"
      return 1
      ;;
  esac
  if "${INTERNAL_LOCAL[@]}" -e "SET GLOBAL rpl_semi_sync_slave_enabled=${semisync_slave_value};" >/dev/null 2>&1; then
    prestop_watchdog_log "internal-local-admin-required-privilege privilege=REPLICATION_SLAVE_ADMIN probe=set-semisync-same-value rc=0"
  else
    prestop_watchdog_log "internal-local-admin-required-privilege privilege=REPLICATION_SLAVE_ADMIN probe=set-semisync-same-value rc=1"
    return 1
  fi
  read_only_value=$("${INTERNAL_LOCAL[@]}" -e "SELECT UPPER(CAST(@@global.read_only AS CHAR));" 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}')
  case "${read_only_value}" in
    0|1|ON|OFF|NO_LOCK|NO_LOCK_NO_ADMIN)
      ;;
    *)
      prestop_watchdog_log "internal-local-admin-required-privilege privilege=READ_ONLY_ADMIN probe=read-read-only-value rc=1 value=${read_only_value:-<empty>}"
      return 1
      ;;
  esac
  if "${INTERNAL_LOCAL[@]}" -e "SET GLOBAL read_only = ${read_only_value};" >/dev/null 2>&1; then
    prestop_watchdog_log "internal-local-admin-required-privilege privilege=READ_ONLY_ADMIN probe=set-read-only-same-value rc=0"
    return 0
  fi
  prestop_watchdog_log "internal-local-admin-required-privilege privilege=READ_ONLY_ADMIN probe=set-read-only-same-value rc=1"
  return 1
}
wait_for_internal_local_admin() {
  local label="${1:-internal-local-admin-ready}"
  local sleep_seconds="${2:-2}"
  local log_every_seconds="${3:-30}"
  local start now elapsed next_log
  start="$(date +%s)"
  next_log=0
  while true; do
    if ensure_internal_local_admin "${label}" && probe_internal_local_admin && internal_local_admin_has_required_privileges; then
      LOCAL=("${INTERNAL_LOCAL[@]}")
      now="$(date +%s)"
      elapsed=$((now - start))
      prestop_watchdog_log "internal-local-admin-ready label=${label} elapsed=${elapsed}s"
      return 0
    fi
    LOCAL=("${ROOT_LOCAL[@]}")
    mark_replication_pending
    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "${elapsed}" -ge "${next_log}" ]; then
      set_fail_closed_read_only "${label}-wait-internal-admin" || true
      prestop_watchdog_log "internal-local-admin-wait label=${label} elapsed=${elapsed}s"
      next_log=$((elapsed + log_every_seconds))
    fi
    sleep "${sleep_seconds}"
  done
}
grant_optional_local_root_privileges() {
  # alpha.64 v1 (Jack 09:35 RED + 10:01 design ack): drop admin
  # bypass privs (READ_ONLY ADMIN / BINLOG ADMIN / CONNECTION ADMIN /
  # REPLICATION SLAVE ADMIN / REPLICATION MASTER ADMIN). Only
  # CMPD_OPTIONAL_MONITOR_PRIVS (BINLOG MONITOR / SLAVE MONITOR)
  # remain — these are read-only monitoring privileges and do NOT
  # bypass @@global.read_only. Tier A (Jack 10:05): failure on a
  # MONITOR grant is allowed to log + continue (best-effort).
  #
  # alpha.64 v3 (Jack 11:14 live-gate RED): use inline QUOTED list
  # to preserve multi-word priv name semantics. Unquoted
  # `for privilege in ${CMPD_OPTIONAL_MONITOR_PRIVS}` would split
  # the string on IFS into 4 single-word tokens (BINLOG / MONITOR
  # / SLAVE / MONITOR) and emit invalid GRANT statements. See
  # constant-declaration block above for full root cause.
  local user="$1"
  local host="$2"
  local label="$3"
  local privilege
  for privilege in "BINLOG MONITOR" "SLAVE MONITOR"; do
    # alpha.108 P0a (Jack 2026-05-29): defense-in-depth wrapper
    # swap ${LOCAL[@]} → ${INTERNAL_LOCAL[@]} (kb_internal_root)
    # so sql_log_bin=0 wrap works regardless of any future
    # hardening pass that might re-trim BINLOG ADMIN from
    # user-facing root @'localhost'/@'127.0.0.1'.
    if "${INTERNAL_LOCAL[@]}" -e "
      SET SESSION sql_log_bin=0;
      GRANT ${privilege} ON *.* TO '${user}'@'${host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    " >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
      prestop_watchdog_log "local-root-optional-privilege privilege=${privilege} label=${label} host=${host} rc=0 tier=monitor-best-effort"
    else
      # Tier A: best-effort MONITOR grant; log 1227_swallowed for
      # observability and continue (do NOT propagate failure to
      # caller since these are monitoring-only and don't gate
      # primary-write/secondary-fence semantics).
      prestop_watchdog_log "local-root-optional-privilege privilege=${privilege} label=${label} host=${host} rc=1 tier=monitor-best-effort 1227_swallowed=true"
    fi
  done
}
set_local_root_account_state() {
  local state="$1"
  local label="$2"
  local user password host mode sql
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  user="$(sql_quote "${MARIADB_ROOT_USER}")"
  password="$(sql_quote "${MARIADB_ROOT_PASSWORD}")"
  for host in localhost 127.0.0.1; do
    if [ "${state}" = "LOCK" ]; then
      # alpha.64 v1 (Jack 09:35 RED): drop SUPER (admin bypass).
      # Use CMPD_SECONDARY_FENCE_GRANT_BODY which excludes SUPER /
      # READ_ONLY ADMIN / BINLOG ADMIN / CONNECTION ADMIN. SUPER
      # bypassed @@global.read_only=ON, defeating the very fence
      # this LOCK path was supposed to enforce.
      #
      # alpha.108 P0a (Jack 2026-05-29): use _LOCAL variant of
      # CMPD_SECONDARY_FENCE_GRANT_BODY which adds BINLOG ADMIN.
      # BINLOG ADMIN is host-scoped to @localhost+@'127.0.0.1' so
      # the chart-internal sql_log_bin=0 wrap below actually
      # takes effect (alpha.64 unintentionally bundled BINLOG
      # ADMIN drop with SUPER drop; BINLOG ADMIN is privilege-
      # orthogonal to SUPER and does NOT bypass @@global.read_only=1
      # — see CMPD_*_LOCAL constant comments above).
      mode="read-replication-admin-only-no-bypass-with-binlog-admin"
      sql="
        SET SESSION sql_log_bin=0;
        CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
        ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
        ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
        REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
        GRANT ${CMPD_SECONDARY_FENCE_GRANT_BODY_LOCAL} ON *.* TO '${user}'@'${host}';
        FLUSH PRIVILEGES;
        SET SESSION sql_log_bin=1;
      "
    else
      # alpha.64 v1: replace GRANT ALL PRIVILEGES with explicit
      # primary grant body (CMPD_EXPLICIT_PRIMARY_GRANT_BODY)
      # aligned with switchover.sh's SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY.
      # GRANT ALL PRIVILEGES bundled SUPER/READ_ONLY ADMIN/BINLOG
      # ADMIN which let user-facing root bypass read_only.
      #
      # alpha.108 P0a (Jack 2026-05-29): use _LOCAL variant for
      # same reason as the LOCK branch above (host-scoped BINLOG
      # ADMIN restoration to close the 6-alpha sql_log_bin=0 silent
      # failure pattern).
      mode="primary-write-no-bypass-with-binlog-admin"
      sql="
        SET SESSION sql_log_bin=0;
        CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
        ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
        ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
        REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
        GRANT ${CMPD_EXPLICIT_PRIMARY_GRANT_BODY_LOCAL} ON *.* TO '${user}'@'${host}' WITH GRANT OPTION;
        FLUSH PRIVILEGES;
        SET SESSION sql_log_bin=1;
      "
    fi
    # alpha.108 P0a (Jack 2026-05-29): defense-in-depth wrapper
    # swap from ${LOCAL[@]} (which begins as ROOT_LOCAL = user-
    # facing root and stays that way until wait_for_internal_
    # local_admin promotes it) to ${INTERNAL_LOCAL[@]} (=
    # kb_internal_root with full admin privileges). Even though
    # the host-scoped CMPD_*_LOCAL GRANT BODY change above is
    # the primary mechanism that closes the sql_log_bin=0 silent
    # failure, using INTERNAL_LOCAL here adds a second
    # independent layer of protection (a future hardening pass
    # that accidentally drops BINLOG ADMIN from user-facing root
    # @'localhost' would no longer regress this fix; reviewer
    # sees explicit kb_internal_root identity rather than the
    # bootstrap-time ambiguous LOCAL identity).
    if "${INTERNAL_LOCAL[@]}" -e "${sql}" >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
      if [ "${state}" = "LOCK" ]; then
        rm -f ${DATA_DIR}/.primary-read-write-ready
      fi
      prestop_watchdog_log "local-root-account-${state} mode=${mode} label=${label} host=${host} rc=0 tier=required"
      grant_optional_local_root_privileges "${user}" "${host}" "${label}"
      continue
    fi
    # Tier B (Jack 10:05): account-state grant is required; failure
    # MUST fail-closed. Caller (set_primary_read_write etc.) checks
    # this rc and does NOT publish ready/role on rc!=0.
    prestop_watchdog_log "local-root-account-${state} mode=${mode} label=${label} host=${host} rc=1 tier=required 1227_swallowed=true fail_closed=true"
    return 1
  done
}
set_remote_root_account_state() {
  local state="$1"
  local label="$2"
  local user host password mode sql
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  user="$(sql_quote "${MARIADB_ROOT_USER}")"
  host="$(sql_quote "${MARIADB_ROOT_HOST:-%}")"
  password="$(sql_quote "${MARIADB_ROOT_PASSWORD}")"
  case "${MARIADB_ROOT_HOST:-%}" in
    localhost|127.0.0.1|::1)
      prestop_watchdog_log "remote-root-account-${state} label=${label} host=${host} rc=0 decision=skip-local-host"
      return 0
      ;;
  esac
  # alpha.80 v1 (Helen): the alpha.77 in-function marker check
  # has been removed. alpha.79 v1 minimalist deleted the marker
  # writer in switchover.sh, so this gate could never trip. Pure
  # dead-code cleanup, no runtime behavior change.
  if [ "${state}" = "LOCK" ]; then
    # alpha.64 v1 (Jack 09:35 RED): drop SUPER (admin bypass).
    # Use CMPD_SECONDARY_FENCE_GRANT_BODY shared with local LOCK.
    mode="read-replication-only-no-bypass"
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
      GRANT ${CMPD_SECONDARY_FENCE_GRANT_BODY} ON *.* TO '${user}'@'${host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
  else
    # alpha.64 v1: replace GRANT ALL PRIVILEGES with explicit
    # CMPD_EXPLICIT_PRIMARY_GRANT_BODY.
    mode="primary-write-no-bypass"
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
      GRANT ${CMPD_EXPLICIT_PRIMARY_GRANT_BODY} ON *.* TO '${user}'@'${host}' WITH GRANT OPTION;
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
  fi
  # alpha.108 P0a (Jack 2026-05-29): defense-in-depth wrapper
  # swap ${LOCAL[@]} → ${INTERNAL_LOCAL[@]} so sql_log_bin=0
  # wrap works on this @'%' grant path even if the @'%'
  # alpha.64 hardening (BINLOG ADMIN dropped, intentionally
  # retained by alpha.108) is ever further tightened.
  if "${INTERNAL_LOCAL[@]}" -e "${sql}" \
    >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
    prestop_watchdog_log "remote-root-account-${state} mode=${mode} label=${label} host=${host} rc=0 tier=required"
    return 0
  fi
  # Tier B (Jack 10:05): remote root account-state grant required;
  # failure MUST fail-closed; caller does NOT publish ready/role.
  prestop_watchdog_log "remote-root-account-${state} mode=${mode} label=${label} host=${host} rc=1 tier=required 1227_swallowed=true fail_closed=true"
  return 1
}
grant_optional_remote_root_privileges() {
  local label="${1:-remote-root-optional-privileges}"
  local user host privilege
  case "${MARIADB_ROOT_HOST:-%}" in
    localhost|127.0.0.1|::1)
      return 0
      ;;
  esac
  user="$(sql_quote "${MARIADB_ROOT_USER}")"
  host="$(sql_quote "${MARIADB_ROOT_HOST:-%}")"
  # alpha.64 v1 (Jack 09:35 RED + 10:01 design ack): drop admin
  # bypass privs (BINLOG ADMIN / READ_ONLY ADMIN / CONNECTION ADMIN).
  # Only CMPD_OPTIONAL_MONITOR_PRIVS (BINLOG MONITOR / SLAVE MONITOR)
  # remain — read-only monitoring privs that don't bypass read_only.
  # Tier A (Jack 10:05): MONITOR grant failure log + continue.
  #
  # alpha.64 v3 (Jack 11:14 live-gate RED): inline QUOTED list to
  # preserve multi-word priv name semantics; see constant block.
  #
  # alpha.108 P0a (Jack 2026-05-29): defense-in-depth wrapper
  # swap ${LOCAL[@]} → ${INTERNAL_LOCAL[@]} so sql_log_bin=0
  # wrap works regardless of which alpha generation user-facing
  # root @'%' grant set takes.
  for privilege in "BINLOG MONITOR" "SLAVE MONITOR"; do
    if "${INTERNAL_LOCAL[@]}" -e "
      SET SESSION sql_log_bin=0;
      GRANT ${privilege} ON *.* TO '${user}'@'${host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    " >> ${DATA_DIR}/log/sql-listener-fence.log 2>&1; then
      prestop_watchdog_log "remote-root-optional-privilege privilege=${privilege} label=${label} host=${host} rc=0 tier=monitor-best-effort"
    else
      prestop_watchdog_log "remote-root-optional-privilege privilege=${privilege} label=${label} host=${host} rc=1 tier=monitor-best-effort 1227_swallowed=true"
    fi
  done
}
lock_remote_root_writes() {
  set_remote_root_account_state "LOCK" "$1" || return 1
  grant_optional_remote_root_privileges "$1" || true
}
unlock_remote_root_writes() {
  set_remote_root_account_state "UNLOCK" "$1"
}
lock_local_root_writes() {
  set_local_root_account_state "LOCK" "$1"
}
unlock_local_root_writes() {
  set_local_root_account_state "UNLOCK" "$1"
}
query_slave_status_verbose() {
  timeout 5 mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -S "${SOCK}" -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}
slave_status_is_healthy() {
  local slave_status="$1"
  [ -n "${slave_status}" ] || return 1
  case "${slave_status}" in
    *"Slave_IO_Running: Yes"*) ;;
    *) return 1 ;;
  esac
  case "${slave_status}" in
    *"Slave_SQL_Running: Yes"*) ;;
    *) return 1 ;;
  esac
  case "${slave_status}" in
    *"Last_IO_Errno: 0"*) ;;
    *) return 1 ;;
  esac
  case "${slave_status}" in
    *"Last_SQL_Errno: 0"*) ;;
    *) return 1 ;;
  esac
}
recover_semisync_slave_health_after_rejoin() {
  local semisync_enabled
  semisync_enabled=$("${LOCAL[@]}" -N -s -e \
    "SELECT @@global.rpl_semi_sync_slave_enabled;" 2>/dev/null || echo "0")
  [ "${semisync_enabled}" = "1" ] || return 0

  local status deadline
  deadline=$((SECONDS + 10))
  while [ $SECONDS -lt $deadline ]; do
    status=$("${LOCAL[@]}" -N -s -e \
      "SHOW STATUS LIKE 'Rpl_semi_sync_slave_status';" 2>/dev/null | awk '{print $2}')
    [ "${status}" = "ON" ] && return 0
    sleep 2
  done

  echo "Rpl_semi_sync_slave_status=OFF after replication rejoin; restarting IO thread"
  "${LOCAL[@]}" -e "STOP SLAVE IO_THREAD; START SLAVE IO_THREAD;" 2>/dev/null || true

  deadline=$((SECONDS + 15))
  while [ $SECONDS -lt $deadline ]; do
    status=$("${LOCAL[@]}" -N -s -e \
      "SHOW STATUS LIKE 'Rpl_semi_sync_slave_status';" 2>/dev/null | awk '{print $2}')
    if [ "${status}" = "ON" ]; then
      echo "Rpl_semi_sync_slave_status recovered to ON after IO thread restart"
      return 0
    fi
    sleep 2
  done

  echo "WARNING: Rpl_semi_sync_slave_status still OFF after IO thread restart"
}
# alpha.99 (Helen 2026-05-25): removed
# slave_status_has_kb_health_check_repairable_error +
# repair_kb_health_check_replication_error functions.
# The "repair" was DELETE FROM kubeblocks.kb_health_check,
# which violated table ownership (kb_health_check is a syncer
# resource, see engines/mariadb/manager.go) and caused the
# very Error 1032 it tried to fix. Iron-evidence repro on
# cluster mdb-repro-1032 2026-05-25 08:03Z confirmed: DELETE
# on secondary removes the row that primary's next Update_rows
# _v1 event expects to find -> 1032 HA_ERR_KEY_NOT_FOUND.
# Without the DELETE the row stays valid, replication applies
# cleanly. syncer's WriteCheck path handles the table
# lifecycle (CREATE fallback included in manager.go).
wait_for_replication_healthy() {
  local label="$1"
  local timeout_seconds="${2:-120}"
  local sleep_seconds="${3:-2}"
  local start now elapsed slave_status evidence_file current_syncer_role
  start="$(date +%s)"
  evidence_file="${DATA_DIR}/log/rejoin-replication-wait.log"
  mkdir -p ${DATA_DIR}/log 2>/dev/null || true
  while true; do
    # alpha.77 v3 (Helen TL): if syncer has flipped this pod to
    # primary in DCS (e.g. a switchover OpsRequest just promoted
    # this candidate), exit the secondary-rejoin wait immediately
    # so the outer wait_for_mariadbd_with_role_reconcile loop can
    # switch into the primary reconcile path on its next tick.
    # Without this short-circuit, this loop will spin up to
    # `timeout_seconds` (default 120s) trying to follow the OLD
    # primary that is no longer the DCS primary, blowing past the
    # switchover candidate-write-ready stage budget.
    #
    # Backward compatibility: when syncer continues to report
    # role=secondary (the normal post-rejoin / lifecycle path),
    # the loop body below runs unchanged. The check itself is
    # bounded by `timeout 3` inside query_local_syncer_role and
    # is best-effort (failure is treated as not-flipped, loop
    # continues). Distinct sentinel log + return code 2 so
    # downstream callers and closeout can distinguish "DCS
    # promoted us mid-rejoin" from a real replication-not-
    # healthy timeout (return 1).
    current_syncer_role="$(query_local_syncer_role || true)"
    if [ "${current_syncer_role}" = "primary" ]; then
      elapsed=$(($(date +%s) - start))
      prestop_watchdog_log "rejoin-replication-exit-on-dcs-primary label=${label} elapsed=${elapsed}s reason=dcs_promoted_during_secondary_rejoin"
      return 2
    fi
    slave_status="$(query_slave_status_verbose || true)"
    if slave_status_is_healthy "${slave_status}"; then
      elapsed=$(($(date +%s) - start))
      prestop_watchdog_log "rejoin-replication-healthy label=${label} elapsed=${elapsed}s"
      return 0
    fi
    now="$(date +%s)"
    elapsed=$((now - start))
    if [ "${elapsed}" -ge "${timeout_seconds}" ]; then
      {
        printf 'timestamp=%s\n' "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
        printf 'label=%s\n' "${label}"
        printf 'decision=replication-not-healthy\n'
        printf 'elapsed_seconds=%s\n' "${elapsed}"
        printf 'slave_status_begin\n'
        if [ -n "${slave_status}" ]; then
          printf '%s\n' "${slave_status}"
        else
          printf '<empty>\n'
        fi
        printf 'slave_status_end\n\n'
      } >> "${evidence_file}" 2>/dev/null || true
      prestop_watchdog_log "rejoin-replication-not-healthy label=${label} elapsed=${elapsed}s"
      return 1
    fi
    sleep "${sleep_seconds}"
  done
}
keep_replica_pending_until_healthy() {
  # alpha.64 v2 (Jack 10:32 HOLD blocker 1): Tier B required LOCK
  # failures MUST propagate rc to caller. Caller pattern is
  # `if ! keep_replica_pending_until_healthy ...; then return 1`,
  # so propagating rc keeps the caller from publishing
  # ready/role on locking failure.
  local label="$1"
  local rc=0 syncer_primary_rc
  mark_replication_pending
  replica_lock_abort_if_syncer_primary "${label}-pending-before-lock"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  lock_remote_root_writes "${label}-pending" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-pending-after-remote-lock"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  set_fail_closed_read_only "${label}-pending" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-pending-after-read-only"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  "${LOCAL[@]}" -e "START SLAVE;" 2>/dev/null || true # tier=error-recovery
  lock_local_root_writes "${label}-pending" || rc=1
  replica_lock_abort_if_syncer_primary "${label}-pending-after-local-lock"
  syncer_primary_rc=$?
  [ "${syncer_primary_rc}" -eq 2 ] && return 2
  if [ "${rc}" -ne 0 ]; then
    prestop_watchdog_log "keep-replica-pending label=${label} rc=1 tier=required fail_closed=true"
    return 1
  fi
  wait_for_replication_healthy "${label}" 120 2
}
publish_replica_after_rejoin_ready() {
  # alpha.64 v2 (Jack 10:32 HOLD blocker 1): Tier B required path.
  # mark_replication_ready (line below) is the publish point; if any
  # required step fails (set_replica_read_only / expose_sql_listener),
  # the function MUST return 1 BEFORE reaching mark_replication_ready.
  local label="$1" replica_rejoin_rc
  keep_replica_pending_until_healthy "${label}-before-expose"
  replica_rejoin_rc=$?
  if [ "${replica_rejoin_rc}" -eq 2 ]; then
    accept_syncer_primary_promotion_from_replica_path "replica-rejoin-before-expose-${label}"
    return $?
  fi
  if [ "${replica_rejoin_rc}" -ne 0 ]; then
    return 1
  fi
  set_replica_read_only "${label}-before-expose"
  replica_rejoin_rc=$?
  if [ "${replica_rejoin_rc}" -eq 2 ]; then
    accept_syncer_primary_promotion_from_replica_path "replica-rejoin-before-expose-lock-${label}"
    return $?
  fi
  if [ "${replica_rejoin_rc}" -ne 0 ]; then
    prestop_watchdog_log "publish-replica-rejoin label=${label} step=before-expose rc=1 tier=required fail_closed=true"
    return 1
  fi
  if ! expose_sql_listener_for_safe_role "${label}"; then
    return 1
  fi
  "${LOCAL[@]}" -e "START SLAVE;" 2>/dev/null || true # tier=error-recovery
  set_replica_read_only "${label}-after-expose"
  replica_rejoin_rc=$?
  if [ "${replica_rejoin_rc}" -eq 2 ]; then
    accept_syncer_primary_promotion_from_replica_path "replica-rejoin-after-expose-lock-${label}"
    return $?
  fi
  if [ "${replica_rejoin_rc}" -ne 0 ]; then
    prestop_watchdog_log "publish-replica-rejoin label=${label} step=after-expose rc=1 tier=required fail_closed=true"
    return 1
  fi
  wait_for_replication_healthy "${label}-after-expose" 120 2
  replica_rejoin_rc=$?
  if [ "${replica_rejoin_rc}" -eq 2 ]; then
    accept_syncer_primary_promotion_from_replica_path "replica-rejoin-after-expose-${label}"
    return $?
  fi
  if [ "${replica_rejoin_rc}" -ne 0 ]; then
    # tier=fail-path-defensive: replication is already
    # known unhealthy; we mark pending and best-effort lock.
    mark_replication_pending
    lock_remote_root_writes "${label}-after-expose-not-healthy" || true # tier=fail-path-defensive
    set_fail_closed_read_only "${label}-after-expose-not-healthy" || true # tier=fail-path-defensive
    lock_local_root_writes "${label}-after-expose-not-healthy" || true # tier=fail-path-defensive
    return 1
  fi
  recover_semisync_slave_health_after_rejoin
  mark_replication_ready
  return 0
}
# alpha.99 (Helen 2026-05-25): removed
# clear_local_kb_health_check_table /
# with_local_read_write_for_health_check_repair /
# prepare_fresh_replica_for_sql_thread_start /
# repair_kb_health_check_replication_error.
# All four wrapped an addon-side DELETE FROM
# kubeblocks.kb_health_check, which broke the syncer's
# ownership of that table and triggered the very 1032 cascade
# they tried to repair. See removed
# slave_status_has_kb_health_check_repairable_error block for
# the iron-evidence reference. The addon now does not touch
# kb_health_check at any lifecycle point; syncer owns
# create/read/write per engines/mariadb/manager.go.
mariadbd_pids() {
  if command -v pidof >/dev/null 2>&1; then
    pidof mariadbd 2>/dev/null || true
    return
  fi
  ps 2>/dev/null | awk '$NF ~ /mariadbd$/ {print $1}'
}
pause_syncer_for_prestop() {
  local rc
  [ -x /tools/syncerctl ] || return 0
  timeout 3 /tools/syncerctl pause >> ${DATA_DIR}/log/prestop-watchdog.log 2>&1
  rc=$?
  prestop_watchdog_log "syncerctl-pause rc=${rc}"
  return 0
}
fence_read_only_for_prestop() {
  timeout 2 "${LOCAL[@]}" -e "SET GLOBAL read_only = NO_LOCK_NO_ADMIN;" \
    >> ${DATA_DIR}/log/prestop-watchdog.log 2>&1 \
    || timeout 2 "${LOCAL[@]}" -e "SET GLOBAL read_only = ON;" \
    >> ${DATA_DIR}/log/prestop-watchdog.log 2>&1 \
    || timeout 2 "${LOCAL[@]}" -e "SET GLOBAL read_only = 1;" \
    >> ${DATA_DIR}/log/prestop-watchdog.log 2>&1 \
    || true
  timeout 2 "${LOCAL[@]}" \
    -e "SELECT NOW(), @@global.read_only, @@global.gtid_binlog_state, @@global.gtid_binlog_pos;" \
    >> ${DATA_DIR}/log/prestop-watchdog.log 2>&1 || true
}
stop_mariadbd_for_prestop() {
  local pids
  pids="$(mariadbd_pids | tr '\n' ' ')"
  if [ -z "${pids}" ]; then
    prestop_watchdog_log "mariadbd pid not found"
    return 0
  fi
  prestop_watchdog_log "term mariadbd pids=${pids}"
  kill -TERM ${pids} 2>/dev/null || true
  sleep 1
  pids="$(mariadbd_pids | tr '\n' ' ')"
  if [ -n "${pids}" ]; then
    prestop_watchdog_log "kill mariadbd pids=${pids}"
    kill -KILL ${pids} 2>/dev/null || true
  fi
}
wait_for_mariadb_local() {
  until "${LOCAL[@]}" -e "SELECT 1" >/dev/null 2>&1; do
    if [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
      prestop_watchdog_log "connection-wait-exit reason=prestop-fence-started"
      return 1
    fi
    if ! kill -0 ${MARIADB_PID} 2>/dev/null; then
      prestop_watchdog_log "connection-wait-exit reason=mariadbd-exited"
      return 1
    fi
    sleep 2
  done
}
start_mariadbd_process() {
  local bind_address="$1"
  local label="$2"
  prestop_watchdog_log "start-mariadbd label=${label} bind_address=${bind_address}"
  # alpha.86 v1 (Helen) — --defaults-extra-file must be the
  # FIRST mariadbd option (MariaDB requires --defaults-* args
  # to come before any other args). The loader file at
  # ${DATA_DIR}/runtime-overrides.cnf is
  # created by init-syncer with the single directive
  # `!includedir ${DATA_DIR}/runtime-overrides.d/`.
  # mariadbd silently accepts an empty dir, so fresh-bootstrap
  # works before any reconfigure has populated the dir.
  # Each successful reconfigure writes a per-parameter
  # `.cnf` file into runtime-overrides.d/; mariadbd picks
  # them up on next restart.
  # alpha.99 (Helen 2026-05-25): REVERT alpha.98's
  # --slave-exec-mode=IDEMPOTENT.
  #
  # Iron-evidence repro on cluster mdb-repro-1032
  # (2026-05-25 08:03Z) showed IDEMPOTENT only stops
  # SQL_THREAD from halting on 1032 — it does NOT
  # repopulate the secondary's empty kb_health_check
  # row. Primary's INSERT...ON DUPLICATE KEY UPDATE
  # always becomes Update_rows in the binlog (because
  # the row exists on primary); secondary therefore
  # never receives Insert_rows. With IDEMPOTENT the
  # secondary table stays empty forever -> syncer's
  # GetOpTimestamp returns no rows -> IsMemberLagging
  # = MaxInt64 -> IsMemberHealthy=false -> same T9
  # switchover deadlock as alpha.96.
  #
  # alpha.99 fix is structural: addon scripts no longer
  # DELETE / repair kubeblocks.kb_health_check (see
  # removed clear/repair/detector block above and the
  # primary_internal_root_write_ready rewrite that
  # uses kubeblocks.kb_addon_write_probe instead). The
  # table now belongs entirely to syncer. STRICT mode
  # is safe again because the secondary's row state
  # always tracks primary's binlog before-image.
  # alpha.100 prototype (Helen 2026-05-25): set gtid_domain_id
  # per-server (= SERVICE_ID = POD_INDEX + 1) so each pod writes
  # its own GTID sequence in a unique domain. Avoids the 1950
  # HA_ERR_GTID_OUT_OF_ORDER cascade that surfaced on alpha.99
  # CM4 (cluster mdb-a99-cm4 2026-05-25 17:27Z): pod-0 wrote
  # 0-1-213 before switchover, pod-1 promoted only catching up
  # to 0-1-211, started writing 0-2-212+; when pod-0 reboots
  # as secondary, applying 0-2-212 with strict_mode against
  # local 0-1-213 (same domain 0) → 1950. With per-server
  # domain, pod-0 writes in domain 1, pod-1 in domain 2; their
  # sequences are independent → no strict-mode conflict.
  # alpha.101 (Helen 2026-05-25): set
  # --rpl-semi-sync-master-wait-point=AFTER_SYNC instead
  # of MariaDB's default AFTER_COMMIT. AFTER_SYNC makes
  # the primary wait for replica ACK BEFORE storage-
  # engine commit (instead of after), so clients do not
  # see commit return until at least one replica has
  # acked the binlog. Aligns mariadb wait_point with
  # MySQL 5.7+/8.0 default. Partial mitigation only:
  # when replica is down for longer than
  # rpl_semi_sync_master_timeout (10s default), both
  # AFTER_SYNC and AFTER_COMMIT fall back to async, so
  # orphan events can still occur during a long pod-1
  # restart. A complete fix requires syncer Demote-time
  # catch-up wait (Path B, separate PR).
  docker-entrypoint.sh mariadbd \
    --defaults-extra-file=${DATA_DIR}/runtime-overrides.cnf \
    --server-id=${SERVICE_ID} \
    --gtid-domain-id=${SERVICE_ID} \
    --log-bin=${DATA_DIR}/binlog/${POD_NAME}-bin \
    --skip-slave-start=ON \
    --read-only=NO_LOCK_NO_ADMIN \
    --thread-cache-size=100 \
    --rpl-semi-sync-master-wait-point=AFTER_SYNC \
    --bind-address="${bind_address}" &
  MARIADB_PID=$!
  prestop_fence_watchdog &
  PRESTOP_WATCHDOG_PID=$!
}
stop_mariadbd_process() {
  local label="$1"
  local i pids
  pids="$(mariadbd_pids | tr '\n' ' ')"
  if [ -z "${pids}" ]; then
    prestop_watchdog_log "stop-mariadbd label=${label} pid-not-found"
    return 0
  fi
  prestop_watchdog_log "stop-mariadbd label=${label} term pids=${pids}"
  kill -TERM ${pids} 2>/dev/null || true
  i=0
  while [ "${i}" -lt 15 ]; do
    pids="$(mariadbd_pids | tr '\n' ' ')"
    [ -z "${pids}" ] && break
    sleep 1
    i=$((i + 1))
  done
  pids="$(mariadbd_pids | tr '\n' ' ')"
  if [ -n "${pids}" ]; then
    prestop_watchdog_log "stop-mariadbd label=${label} kill pids=${pids}"
    kill -KILL ${pids} 2>/dev/null || true
  fi
  wait ${MARIADB_PID} 2>/dev/null || true
}
expose_sql_listener_for_safe_role() {
  # alpha.64 v2 (Jack 10:32 HOLD blocker 1): Tier B required path.
  # touch .sql-listener-ready below is the publish point that lets
  # the runtime accept TCP traffic; required local LOCK + read_only
  # MUST hold BEFORE we open the listener. Failure of either MUST
  # return 1 BEFORE touching .sql-listener-ready.
  local label="$1"
  if [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
    prestop_watchdog_log "skip-sql-listener-expose label=${label} reason=prestop-fence-started"
    mark_replication_pending
    return 1
  fi
  if [ -f "${DATA_DIR}/.sql-listener-ready" ] && mariadbd_listen_on_all_interfaces; then
    return 0
  fi
  if [ -f "${DATA_DIR}/.sql-listener-ready" ]; then
    prestop_watchdog_log "sql-listener-expose-stale-marker label=${label} reason=listener-not-wildcard"
  fi
  mark_replication_pending
  prestop_watchdog_log "sql-listener-expose-begin label=${label}"
  stop_mariadbd_process "sql-listener-${label}"
  start_mariadbd_process "0.0.0.0" "sql-listener-${label}"
  if ! wait_for_mariadb_local; then
    wait ${MARIADB_PID}
    exit $?
  fi
  if ! set_fail_closed_read_only "sql-listener-${label}"; then
    prestop_watchdog_log "sql-listener-expose label=${label} step=set-read-only rc=1 tier=required fail_closed=true"
    return 1
  fi
  if ! lock_local_root_writes "sql-listener-${label}"; then
    prestop_watchdog_log "sql-listener-expose label=${label} step=lock-local-root rc=1 tier=required fail_closed=true"
    return 1
  fi
  touch ${DATA_DIR}/.sql-listener-ready
  prestop_watchdog_log "sql-listener-expose-complete label=${label}"
}
# alpha.107 (Doc B Rule 6): direct verify mariadbd is listening on
# 0.0.0.0:3306 (or :::3306) — `.sql-listener-ready` marker semantic
# = "mariadbd already rebound past 127.0.0.1 bootstrap". Read
# /proc/net/tcp (IPv4) + /proc/net/tcp6 (IPv6); listen state = 0A;
# port 3306 = hex 0CEA. IPv4 wildcard local_address = 00000000:0CEA;
# IPv6 wildcard = 00000000000000000000000000000000:0CEA. Either
# present passes; only 127.0.0.1:3306 (0100007F:0CEA) → fail.
mariadbd_listen_on_all_interfaces() {
  local f
  for f in /proc/net/tcp /proc/net/tcp6; do
    [ -r "$f" ] || continue
    awk 'NR>1 && $4=="0A" {print $2}' "$f" | while read -r addr; do
      case "$addr" in
        00000000:0CEA) echo wildcard; break ;;
        00000000000000000000000000000000:0CEA) echo wildcard; break ;;
      esac
    done | grep -q wildcard && return 0
  done
  return 1
}
is_semisync_mode_env() {
  [ "${MARIADB_REPLICATION_MODE:-}" = "semisync" ]
}
ensure_semisync_primary_role() {
  local label="${1:-unknown}"
  if ! is_semisync_mode_env; then
    return 0
  fi
  if "${INTERNAL_LOCAL[@]}" -e "SET GLOBAL rpl_semi_sync_master_enabled=1; SET GLOBAL rpl_semi_sync_slave_enabled=0;" >/dev/null 2>&1; then
    prestop_watchdog_log "semisync-role-shape label=${label} role=primary master=1 slave=0 rc=0"
    return 0
  fi
  prestop_watchdog_log "semisync-role-shape label=${label} role=primary rc=1"
  return 1
}
ensure_semisync_replica_role() {
  local label="${1:-unknown}"
  if ! is_semisync_mode_env; then
    return 0
  fi
  if "${INTERNAL_LOCAL[@]}" -e "SET GLOBAL rpl_semi_sync_master_enabled=0; SET GLOBAL rpl_semi_sync_slave_enabled=1;" >/dev/null 2>&1; then
    prestop_watchdog_log "semisync-role-shape label=${label} role=secondary master=0 slave=1 rc=0"
    return 0
  fi
  prestop_watchdog_log "semisync-role-shape label=${label} role=secondary rc=1"
  return 1
}
reset_semisync_master_ack_receiver_if_enabled() {
  local label="${1:-unknown}"
  if ! is_semisync_mode_env; then
    prestop_watchdog_log "skip-semisync-master-ack-reset label=${label} reason=replication-mode-not-semisync mode=${MARIADB_REPLICATION_MODE:-<empty>}"
    return 0
  fi
  "${LOCAL[@]}" -e "SET GLOBAL rpl_semi_sync_master_enabled=0; SET GLOBAL rpl_semi_sync_master_enabled=1;" 2>/dev/null || true
}
expose_sql_listener_for_primary_role() {
  local label="$1"
  if [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
    prestop_watchdog_log "skip-sql-listener-primary-expose label=${label} reason=prestop-fence-started"
    mark_replication_pending
    return 1
  fi
  # alpha.107 (Doc B Rule 6): gate reconciled-existing fast path on
  # direct mariadbd bind verify. Without this, a stale
  # `.sql-listener-ready` marker (reaper bug, PVC residue, etc.)
  # lets us skip the actual rebind and leave mariadbd on 127.0.0.1
  # bootstrap — pods can't be reached by Service traffic. If the
  # marker exists but mariadbd is still bootstrap-bound, fall
  # through to the fresh-listener path below.
  if [ -f "${DATA_DIR}/.sql-listener-ready" ] && mariadbd_listen_on_all_interfaces; then
    "${LOCAL[@]}" -e "STOP SLAVE; RESET SLAVE ALL;" 2>/dev/null || true
    reset_semisync_master_ack_receiver_if_enabled "primary-existing-listener-${label}"
    if ! ensure_semisync_primary_role "primary-existing-listener-${label}"; then
      mark_replication_pending
      prestop_watchdog_log "sql-listener-primary-expose-failed label=${label} reason=existing-listener-semisync-role-shape"
      return 1
    fi
    if set_primary_read_write "${label}"; then
      touch ${DATA_DIR}/.sql-listener-ready
      prestop_watchdog_log "sql-listener-primary-existing-reconciled label=${label}"
      return 0
    fi
    mark_replication_pending
    prestop_watchdog_log "sql-listener-primary-expose-failed label=${label} reason=existing-listener-local-write-not-ready"
    return 1
  fi
  mark_replication_pending
  prestop_watchdog_log "sql-listener-primary-expose-begin label=${label}"
  stop_mariadbd_process "sql-listener-primary-${label}"
  start_mariadbd_process "0.0.0.0" "sql-listener-primary-${label}"
  if ! wait_for_mariadb_local; then
    wait ${MARIADB_PID}
    exit $?
  fi
  "${LOCAL[@]}" -e "STOP SLAVE; RESET SLAVE ALL;" 2>/dev/null || true
  reset_semisync_master_ack_receiver_if_enabled "primary-fresh-listener-${label}"
  if ! ensure_semisync_primary_role "primary-fresh-listener-${label}"; then
    mark_replication_pending
    prestop_watchdog_log "sql-listener-primary-expose-failed label=${label} reason=fresh-listener-semisync-role-shape"
    return 1
  fi
  if ! set_primary_read_write "${label}"; then
    mark_replication_pending
    prestop_watchdog_log "sql-listener-primary-expose-failed label=${label}"
    return 1
  fi
  touch ${DATA_DIR}/.sql-listener-ready
  prestop_watchdog_log "sql-listener-primary-expose-complete label=${label}"
}
query_local_syncer_role() {
  [ -x /tools/syncerctl ] || return 1
  timeout 3 /tools/syncerctl --host 127.0.0.1 --port 3601 getrole 2>/dev/null | tr -d '\r\n'
}
query_primary_service_server_id() {
  timeout 3 mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@server_id;" 2>/dev/null || true
}
local_primary_role_published() {
  [ ! -f "${DATA_DIR}/master.info" ] && \
  [ -f "${DATA_DIR}/.primary-read-write-ready" ] && \
  [ -f "${DATA_DIR}/.sql-listener-ready" ] && \
  mariadbd_listen_on_all_interfaces
}
local_user_table_count() {
  "${LOCAL[@]}" -e "
    SELECT COUNT(*)
    FROM information_schema.TABLES
    WHERE TABLE_SCHEMA NOT IN ('information_schema', 'mysql', 'performance_schema', 'sys', 'kubeblocks');
  " 2>/dev/null | tr -d '\r' | awk 'NF {print $1; exit}'
}
local_has_user_tables() {
  local table_count
  table_count="$(local_user_table_count || echo unknown)"
  case "${table_count}" in
    ''|*[!0-9]*)
      prestop_watchdog_log "runtime-secondary-follow-user-table-count rc=1 value=${table_count:-<empty>}"
      return 0
      ;;
  esac
  prestop_watchdog_log "runtime-secondary-follow-user-table-count rc=0 value=${table_count}"
  [ "${table_count}" -gt 0 ]
}
reconcile_sql_listener_for_syncer_primary_once() {
  local now primary_sid role
  [ ! -f "${DATA_DIR}/.prestop-fence-started" ] || return 0
  # alpha.80 v1 (Helen): the alpha.76 `switchover_fence_active_is_fresh`
  # early-skip has been removed. alpha.79 v1 minimalist deleted the
  # marker writer in switchover.sh, so this check could never observe
  # a fresh marker and always fell through. Pure dead-code cleanup,
  # no runtime behavior change.
  if [ -f "${DATA_DIR}/.sql-listener-ready" ]; then
    role="$(query_local_syncer_role || true)"
    [ "${role}" = "primary" ] || return 0
    if [ -f "${DATA_DIR}/.primary-read-write-ready" ] && [ ! -f "${DATA_DIR}/.remote-root-fence-role" ] && [ ! -f "${DATA_DIR}/master.info" ] && mariadbd_listen_on_all_interfaces; then
      return 0
    fi
    prestop_watchdog_log "runtime-primary-listener-reconcile-repair-begin reason=primary-role-state-drift role=${role}"
    # alpha.110 P0a URGENT Direction E: pass "-no-writecheck" suffix
    # to skip primary_local_root_write_ready syncerctl-writecheck in
    # the repair path. Each loop iteration's writecheck INSERTs into
    # kb_health_check generating 1 binlog event per fire; in Round
    # 1c-G 2nd this fired 18 times in 2.5min on mdb-async-10271 pod-0
    # accumulating 18 orphan events that caused post-reconfigure
    # switchover GTID divergence + alpha.60 fail-closed. Skipping the
    # writecheck here removes the orphan event source while preserving
    # primary_internal_root_write_ready (kb_addon_write_probe addon-
    # owned with explicit SET sql_log_bin=0) + marker emit + role
    # probe + read_only management + lock/unlock logic.
    expose_sql_listener_for_primary_role "syncer-promoted-primary-existing-listener-no-writecheck" || return 1
    mark_replication_ready
    prestop_watchdog_log "runtime-primary-listener-reconcile-repair-complete role=${role}"
    return 0
  fi
  if [ "${POD_INDEX}" -gt 0 ] && [ ! -f "${DATA_DIR}/master.info" ]; then
    now="$(date +%s)"
    if [ "${now}" -lt "${SYNCER_PRIMARY_BOOTSTRAP_GRACE_UNTIL}" ]; then
      prestop_watchdog_log "runtime-primary-listener-reconcile-defer reason=fresh-bootstrap-grace pod_index=${POD_INDEX}"
      return 0
    fi
  fi
  role="$(query_local_syncer_role || true)"
  [ "${role}" = "primary" ] || return 0
  primary_sid="$(query_primary_service_server_id || true)"
  if [ -n "${primary_sid}" ] && [ "${primary_sid}" != "${SERVICE_ID}" ]; then
    prestop_watchdog_log "runtime-primary-listener-reconcile-override reason=dcs-primary-overrides-service-routing primary_sid=${primary_sid} service_id=${SERVICE_ID} syncer_role=${role}"
  fi
  prestop_watchdog_log "runtime-primary-listener-reconcile-begin role=${role}"
  expose_sql_listener_for_primary_role "syncer-promoted-primary" || return 1
  mark_replication_ready
  prestop_watchdog_log "runtime-primary-listener-reconcile-complete role=${role}"
}
configure_replication_from_primary_service_once() {
  # alpha.64 v2 (Jack 10:32 HOLD blocker 1): Tier B required path.
  # set_replica_read_only failure means the replica's lock state
  # is not safe; we MUST return 1 so caller does not interpret
  # this iteration as a successful follow attempt.
  local label="${1:-runtime-secondary-follow}"
  local primary_sid master_gtid local_gtid slave_status replica_rejoin_rc
  mark_replication_pending
  set_replica_read_only "${label}-enter"
  replica_rejoin_rc=$?
  if [ "${replica_rejoin_rc}" -eq 2 ]; then
    accept_syncer_primary_promotion_from_replica_path "${label}-enter-lock"
    return $?
  fi
  if [ "${replica_rejoin_rc}" -ne 0 ]; then
    prestop_watchdog_log "configure-replication-from-primary label=${label} step=enter-set-replica-read-only rc=1 tier=required fail_closed=true"
    return 1
  fi
  primary_sid="$(query_primary_service_server_id || true)"
  if [ -z "${primary_sid}" ] || [ "${primary_sid}" = "${SERVICE_ID}" ]; then
    prestop_watchdog_log "runtime-secondary-follow-configure-defer label=${label} reason=primary-service-not-peer primary_sid=${primary_sid:-<empty>} service_id=${SERVICE_ID}"
    return 1
  fi
  if local_has_user_tables && fail_closed_for_gtid_divergence; then
    prestop_watchdog_log "runtime-secondary-follow-configure-blocked label=${label} reason=gtid-divergence"
    return 1
  fi
  master_gtid=$(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@global.gtid_binlog_pos;" 2>/dev/null || echo "")
  local_gtid=$("${LOCAL[@]}" -e "SELECT @@global.gtid_slave_pos;" 2>/dev/null || echo "")
  prestop_watchdog_log "runtime-secondary-follow-configure-begin label=${label} primary_sid=${primary_sid} service_id=${SERVICE_ID} local_gtid=${local_gtid:-<empty>} primary_gtid=${master_gtid:-<empty>}"
  if [ -z "${local_gtid}" ]; then
    if ! "${LOCAL[@]}" -e "
      STOP SLAVE;
      CHANGE MASTER TO
        MASTER_HOST='${PRIMARY_HOST}',
        MASTER_USER='${MARIADB_REPL_USER:-kb_replicator}',
        MASTER_PASSWORD='${MARIADB_ROOT_PASSWORD}',
        MASTER_USE_GTID=slave_pos,
        MASTER_CONNECT_RETRY=10;
      START SLAVE IO_THREAD;
    " 2>/dev/null; then
      prestop_watchdog_log "runtime-secondary-follow-configure-io-failed label=${label}"
      return 1
    fi
    # alpha.99 (Helen 2026-05-25): removed
    # prepare_fresh_replica_for_sql_thread_start call. That
    # function used to DELETE FROM kubeblocks.kb_health_check
    # before SQL_THREAD start, which empties the secondary's
    # row right before replication tries to apply primary's
    # Update_rows_v1 events and triggers 1032. Without the
    # DELETE the local row (if any) matches primary's
    # before-image (because it was last set by replication
    # from this same primary lineage), so START SLAVE
    # SQL_THREAD applies cleanly.
    if ! "${LOCAL[@]}" -e "START SLAVE SQL_THREAD;" 2>/dev/null; then
      # tier=error-recovery: SQL thread start has already failed.
      # mark_replication_pending + best-effort defensive locks +
      # function returns 1.
      mark_replication_pending
      set_fail_closed_read_only "runtime-secondary-follow-sql-thread-start-failed" || true # tier=error-recovery
      lock_local_root_writes "runtime-secondary-follow-sql-thread-start-failed" || true # tier=error-recovery
      prestop_watchdog_log "runtime-secondary-follow-configure-sql-failed label=${label}"
      return 1
    fi
  else
    if ! "${LOCAL[@]}" -e "
      STOP SLAVE;
      CHANGE MASTER TO
        MASTER_HOST='${PRIMARY_HOST}',
        MASTER_USER='${MARIADB_REPL_USER:-kb_replicator}',
        MASTER_PASSWORD='${MARIADB_ROOT_PASSWORD}',
        MASTER_USE_GTID=slave_pos,
        MASTER_CONNECT_RETRY=10;
      START SLAVE;
    " 2>/dev/null; then
      prestop_watchdog_log "runtime-secondary-follow-configure-start-failed label=${label}"
      return 1
    fi
  fi
  slave_status="$(query_slave_status_verbose || true)"
  if [ -z "${slave_status}" ]; then
    prestop_watchdog_log "runtime-secondary-follow-configure-no-slave-status label=${label}"
    return 1
  fi
  if publish_replica_after_rejoin_ready "${label}"; then
    prestop_watchdog_log "runtime-secondary-follow-configure-complete label=${label} primary_sid=${primary_sid}"
    return 0
  fi
  if local_has_user_tables && fail_closed_for_gtid_divergence; then
    prestop_watchdog_log "runtime-secondary-follow-configure-blocked label=${label} reason=gtid-divergence-after-configure"
    return 1
  fi
  prestop_watchdog_log "runtime-secondary-follow-configure-not-healthy label=${label}"
  return 1
}
recover_empty_existing_slave_config_once() {
  local label="${1:-existing-slave-config}"
  local slave_status
  slave_status="$(query_slave_status_verbose || true)"
  [ -z "${slave_status}" ] || return 1
  prestop_watchdog_log "existing-slave-config-reconfigure-begin label=${label} reason=empty-runtime-slave-status"
  if configure_replication_from_primary_service_once "${label}-empty-runtime-slave-status"; then
    prestop_watchdog_log "existing-slave-config-reconfigure-complete label=${label}"
    return 0
  fi
  prestop_watchdog_log "existing-slave-config-reconfigure-defer label=${label}"
  return 1
}
reconcile_sql_listener_for_syncer_secondary_once() {
  # Tier B required path: a runtime secondary may be published only
  # after replica fencing and the SQL listener gate both converge.
  local role slave_status slave_rejoin_rc
  [ ! -f "${DATA_DIR}/.prestop-fence-started" ] || return 0
  role="$(query_local_syncer_role || true)"
  [ "${role}" = "secondary" ] || return 0
  set_replica_read_only "runtime-secondary-reconcile"
  slave_rejoin_rc=$?
  if [ "${slave_rejoin_rc}" -eq 2 ]; then
    accept_syncer_primary_promotion_from_replica_path "runtime-secondary-reconcile-lock"
    return $?
  fi
  if [ "${slave_rejoin_rc}" -ne 0 ]; then
    mark_replication_pending
    prestop_watchdog_log "runtime-secondary-listener-reconcile role=${role} step=set-replica-read-only rc=1 tier=required fail_closed=true"
    return 1
  fi
  slave_status="$(query_slave_status_verbose || true)"
  if slave_status_is_healthy "${slave_status}"; then
    if publish_replica_after_rejoin_ready "runtime-secondary-reconcile"; then
      prestop_watchdog_log "runtime-secondary-listener-reconcile-ready role=${role}"
      return 0
    fi
    prestop_watchdog_log "runtime-secondary-listener-reconcile-pending-after-publish role=${role}"
    return 1
  fi
  if configure_replication_from_primary_service_once "runtime-secondary-follow"; then
    prestop_watchdog_log "runtime-secondary-listener-reconcile-ready-after-configure role=${role}"
    return 0
  fi
  mark_replication_pending
  prestop_watchdog_log "runtime-secondary-listener-reconcile-pending role=${role}"
}
wait_for_mariadbd_with_role_reconcile() {
  local rc=0
  while kill -0 "${MARIADB_PID}" 2>/dev/null; do
    reconcile_sql_listener_for_syncer_secondary_once || true
    reconcile_sql_listener_for_syncer_primary_once || true
    sleep 1
  done
  wait "${MARIADB_PID}" || rc=$?
  return "${rc}"
}
prestop_fence_watchdog() {
  local fired=false
  local iter=0
  while true; do
    if [ -f "${DATA_DIR}/.prestop-fence-started" ]; then
      iter=$((iter + 1))
      if [ "${fired}" = "false" ]; then
        fired=true
        prestop_watchdog_log "marker-detected pod=${POD_NAME:-unknown} mariadb_pid=${MARIADB_PID:-unknown}"
        touch ${DATA_DIR}/.prestop-fence-watchdog-active 2>/dev/null || true
      fi
      mark_replication_pending
      if [ $((iter % 5)) -eq 1 ]; then
        pause_syncer_for_prestop
      fi
      fence_read_only_for_prestop
      stop_mariadbd_for_prestop
      sleep 1
      continue
    fi
    kill -0 "${MARIADB_PID}" 2>/dev/null || break
    sleep 0.2
  done
  if [ "${fired}" = "true" ]; then
    prestop_watchdog_log "exit"
  fi
}

# Reconcile runtime override files with ConfigMap before starting
# mariadbd. A disrupted reconfigureAction (pod killed mid-apply)
# can leave stale values in runtime-overrides.d/ that would
# override the controller's ConfigMap on next startup.
if [ -r /scripts/reconcile-runtime-overrides.sh ]; then
  sh /scripts/reconcile-runtime-overrides.sh || true
fi

# Start local-only until the pod has a safe role. During replacement
# startup, read_only does not block privileged root writes in MariaDB,
# so root write privileges are fenced until the pod is a confirmed
# primary or a healthy replica.
start_mariadbd_process "127.0.0.1" "bootstrap-local-only"

# Wait for MariaDB to accept connections
if ! wait_for_mariadb_local; then
  wait ${MARIADB_PID}
  exit $?
fi
wait_for_internal_local_admin "startup-before-role-decision"
# tier=startup-defensive: pre-role-decision defensive locks. Role
# has not been determined yet; subsequent role-decision branches
# each install their own required Tier B locks (set_replica_read_only,
# expose_sql_listener_for_*_role) before publishing ready/role.
lock_local_root_writes "startup-before-role-decision-pre-remote" || true # tier=startup-defensive
lock_remote_root_writes "startup-before-role-decision" || true # tier=startup-defensive
set_fail_closed_read_only "startup-before-role-decision" || true # tier=startup-defensive
lock_local_root_writes "startup-before-role-decision" || true # tier=startup-defensive

# Determine role by querying the primary service VIP.
# timeout 10 prevents an indefinite hang if the primary is temporarily unresponsive
# (e.g. its semi-sync ACK receiver is stalled) — treat it as "no primary".
PRIMARY_SID=$(timeout 10 mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
  -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@server_id;" 2>/dev/null || echo "")

# Check for existing slave config.
# Use tabular SHOW SLAVE STATUS (not \G) because -N suppresses field names in \G format.
SLAVE_STATUS=$("${LOCAL[@]}" -e "SHOW SLAVE STATUS;" 2>/dev/null)

if [ "${PRIMARY_SID}" = "${SERVICE_ID}" ]; then
  # Primary service routes to us — we are the current primary.
  # Clear any stale slave config and mark initialization as complete.
  if ! expose_sql_listener_for_primary_role "primary-service-route"; then
    wait ${MARIADB_PID}
    exit 1
  fi
  mark_replication_ready
  echo "Starting as primary (server_id=${SERVICE_ID})"
elif [ -n "${SLAVE_STATUS}" ]; then
  # We have existing slave config from a previous run.
  # Do not let an existing datadir self-elect while the primary service is
  # temporarily empty. A terminating old primary can otherwise publish stale
  # local transactions as the new source of truth.
  if fail_closed_for_gtid_divergence; then
    wait ${MARIADB_PID}
    exit 1
  fi
  if [ "${POD_INDEX}" = "0" ] && [ -z "${PRIMARY_SID}" ]; then
    # alpha.92 (Helen 2026-05-24, live N=1 first-blocker from
    # vcluster mariadb-test5 kubeblocks-tests async cluster
    # mdb-async-98800): after a rolling restart of pod-0 (which
    # had been promoted to primary then demoted by switchover),
    # pod-0 starts up with existing slave config (master.info
    # pointing to pod-1, the new primary). At the moment its
    # PRIMARY_SID resolver fires there is a race window where
    # pod-1 has not yet finished self-electing / publishing as
    # primary in the service VIP, so PRIMARY_SID resolves empty.
    # Previously this dropped straight into
    # block_existing_datadir_self_election_without_primary which
    # marks .replication-pending and exits; no further code
    # re-evaluates primary visibility, leaving pod-0 stuck in
    # the pending state forever (syncer HA loop reports
    # "follow failed: replication-pending marker exists" every
    # second; cluster never reaches Running phase). This trap
    # is the merged-CmpD analogue of the alpha.11 single-shot
    # vs bounded-retry rejoin gate documented in
    # docs/cases/mariadb/rejoin-gate-single-shot-vs-bounded
    # -wait-case.md; cmpd-replication.yaml had a similar fix
    # path via finalize_replication_rejoin_ready_gate but
    # merged CmpD was branched off cmpd-semisync.yaml which
    # never had that fix.
    #
    # Fix: wrap the no-primary branch in a bounded retry loop.
    # Every 5s re-resolve PRIMARY_SID. If it appears (the new
    # primary's self-election + DCS publish converges), fall
    # into the existing-slave-config rejoin path (the else
    # branch below). If PRIMARY_SID stays empty for the full
    # MARIADB_NO_PRIMARY_RETRY_BUDGET_SECONDS budget (default
    # 60s — enough for a healthy syncer to elect and publish
    # without being so long it blocks legitimate "primary
    # really is gone, do not self-elect" semisync semantics),
    # fall back to the original mark-pending-and-exit
    # behavior so pod-0 does not silently self-elect after a
    # genuine primary outage. The waiting loop keeps
    # set_fail_closed_read_only + lock_local_root_writes
    # in place via the startup-before-role-decision setup
    # already done at lines 1927-1930.
    # alpha.106 (Jack 2026-05-29) Round 1c-C async T6
    # Stop/Start exposed 60s is not enough when both pods are
    # stopped and started together: pod-1 can take 70-100s
    # from new containerCreating to "mariadbd ready for
    # connections" under vcluster CPU/IO contention. With a
    # 60s budget pod-0 falls through to
    # block_existing_datadir_self_election_without_primary,
    # writes `.replication-pending` and never returns. The
    # alpha.106 reaper in replication-roleprobe.sh is the
    # main self-heal path; extending this budget to 180s
    # reduces how often the reaper has to fire and avoids
    # the visible "Cluster Failed for N minutes" window on
    # the first roleProbe tick. 180s is well under the
    # InstanceSet startupProbe budget so it does not push
    # pod-0 past KB's NotReady threshold.
    no_primary_budget="${MARIADB_NO_PRIMARY_RETRY_BUDGET_SECONDS:-180}"
    no_primary_deadline=$((SECONDS + no_primary_budget))
    while [ $SECONDS -lt $no_primary_deadline ]; do
      echo "pod-0 startup: no primary visible yet, polling every 5s for up to ${no_primary_budget}s before deciding (alpha.92 bounded rejoin retry)"
      sleep 5
      PRIMARY_SID=$(timeout 10 mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
        -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@server_id;" 2>/dev/null || echo "")
      [ -n "${PRIMARY_SID}" ] && break
      reconcile_sql_listener_for_syncer_primary_once || true
      if local_primary_role_published; then
        echo "pod-0 startup: accepted local syncer primary promotion while Primary Service is empty"
        break
      fi
    done
    if [ -z "${PRIMARY_SID}" ] && ! local_primary_role_published; then
      blocked_self_election_resolved=false
      if block_existing_datadir_self_election_without_primary; then
        while true; do
          reconcile_sql_listener_for_syncer_primary_once || true
          if local_primary_role_published; then
            echo "pod-0 accepted syncer primary promotion after blocked self-election"
            blocked_self_election_resolved=true
            break
          fi
          if publish_replica_after_rejoin_ready "existing-slave-config"; then
            echo "Resumed replication from existing slave config after blocked self-election"
            blocked_self_election_resolved=true
            break
          fi
          if fail_closed_for_gtid_divergence; then
            wait ${MARIADB_PID}
            exit 1
          fi
          if recover_empty_existing_slave_config_once "existing-slave-config-blocked-self-election"; then
            echo "Reconfigured replication from Primary Service after existing slave runtime status disappeared"
            blocked_self_election_resolved=true
            break
          fi
          echo "pod-0 startup: blocked self-election, awaiting syncer promotion or primary Service, retrying in 5s."
          sleep 5
        done
      fi
      if [ "${blocked_self_election_resolved}" != "true" ]; then
        if ! expose_sql_listener_for_primary_role "stale-slave-no-primary"; then
          wait ${MARIADB_PID}
          exit 1
        fi
        mark_replication_ready
        echo "Starting as primary (pod-0 with stale slave config, no primary found after ${no_primary_budget}s wait)"
      fi
      PRIMARY_SID=""  # signal: resolved locally; do not fall through to rejoin
    fi
  fi
  # alpha.92 fall-through: when PRIMARY_SID is now non-empty
  # (either set on initial resolve, or appeared during the
  # bounded retry above), drop into the existing-slave-config
  # rejoin loop. PRIMARY_SID="" means we already self-elected
  # in the no-primary branch above and should skip rejoin.
  if [ -n "${PRIMARY_SID}" ] && [ "${PRIMARY_SID}" != "${SERVICE_ID}" ]; then
    while true; do
      reconcile_sql_listener_for_syncer_primary_once || true
      if local_primary_role_published; then
        echo "Existing slave config accepted syncer primary promotion"
        break
      fi
      if publish_replica_after_rejoin_ready "existing-slave-config"; then
        echo "Resumed replication from existing slave config"
        break
      fi
      if fail_closed_for_gtid_divergence; then
        wait ${MARIADB_PID}
        exit 1
      fi
      if recover_empty_existing_slave_config_once "existing-slave-config"; then
        echo "Reconfigured replication from Primary Service after existing slave runtime status disappeared"
        break
      fi
      echo "Existing slave config is not healthy yet; keeping replication pending and read-only, retrying in 5s."
      sleep 5
    done
  fi
elif [ -n "${PRIMARY_SID}" ] || [ "${POD_INDEX}" -gt 0 ]; then
  # No slave config; we need to configure replication from the primary.
  # Loop indefinitely until replication is successfully configured:
  #   1. Find the primary (a server_id different from ours) — retry every 3s
  #   2. Run CHANGE MASTER TO; START SLAVE
  #   3. Verify SHOW SLAVE STATUS is non-empty (config stored); on failure,
  #      sleep 5s and retry from step 1.
  # .replication-pending stays set throughout so roleProbe does not publish a
  # role, preventing a spurious "primary" report and the resulting split-brain race.
  #
  # Chart-side self-election paths (Path A 60s any-pod / Path B 30s non-pod-0)
  # were removed 2026-05-05 to fix cycle 4 semisync n01 double-primary race
  # (pod-0 default-primary by index + pod-1 self-elect after 30s both firing).
  # Primary election now belongs entirely to syncer/DCS:
  #   - Fresh bootstrap entry point: pod-0 default-primary by index (else branch below)
  #   - Failover: syncer IsHealthiestMember fence (apecloud/syncer PR #142) +
  #     AttemptAcquireLease + Promote()
  # The loop never gives up on its own — chart waits for primary to appear,
  # never self-elects. If pod-0 never comes (broken image), this pod stays in
  # the loop and the cluster waits for kbagent restart / operator intervention.
  # That is the intended trade-off of "primary election belongs to syncer/DCS".
  #
  # Set fail-closed read_only BEFORE entering the wait loop. mariadbd starts
  # read-only from the command line, and this explicit set plus the local
  # root write fence keeps the pod unwritable while role is unresolved.
  # Cycle 6 (alpha.18) caught the previous default-writable behavior as a SQL
  # invariant failure: pod-0 default-primary read_only=0 plus pod-1 waiting in
  # the loop with default read_only=0 = two writable instances.
  # tier=startup-defensive: pre-role-decision waiting loop entry;
  # subsequent publish_replica_after_rejoin_ready (Tier B required)
  # is the actual ready/role publish point.
  set_fail_closed_read_only "wait-primary-loop-entry" || true # tier=startup-defensive
  lock_local_root_writes "wait-primary-loop-entry" || true # tier=startup-defensive
  _no_primary_iters=0
  while true; do
    # Step 1: find primary (timeout 10 prevents hang if primary unresponsive)
    PRIMARY_SID=$(timeout 10 mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@server_id;" 2>/dev/null || echo "")
    if [ -z "${PRIMARY_SID}" ] || [ "${PRIMARY_SID}" = "${SERVICE_ID}" ]; then
      # alpha.12 (r35 T15): .sql-listener-ready can be stale after
      # preStop kills the exposed mariadbd and kbagent restarts a
      # bootstrap-local-only 127.0.0.1 process. Always let the
      # syncer-primary reconciler re-check the real listener state.
      reconcile_sql_listener_for_syncer_primary_once || true
      if local_primary_role_published; then
        echo "Starting as primary after syncer promoted this pod"
        break
      fi
      _no_primary_iters=$((_no_primary_iters + 1))
      # Observability: log every 30s so external watchers see we are still waiting
      # for primary, not silently stuck. Does not change behavior.
      if [ $((_no_primary_iters % 10)) -eq 0 ]; then
        echo "INFO: primary not found at iter=${_no_primary_iters} (~$((_no_primary_iters * 3))s elapsed); still waiting for syncer/DCS to elect a primary"
      fi
      sleep 3
      continue
    fi
    # Step 2: configure replication
    if fail_closed_for_gtid_divergence; then
      wait ${MARIADB_PID}
      exit 1
    fi
    MASTER_GTID=$(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      -P3306 -h"${PRIMARY_HOST}" -N -s -e "SELECT @@global.gtid_binlog_pos;" 2>/dev/null)
    LOCAL_GTID=$("${LOCAL[@]}" -e "SELECT @@global.gtid_slave_pos;" 2>/dev/null || echo "")
    if [ -z "${LOCAL_GTID}" ]; then
      if ! "${LOCAL[@]}" -e "
        STOP SLAVE;
        CHANGE MASTER TO
          MASTER_HOST='${PRIMARY_HOST}',
          MASTER_USER='${MARIADB_REPL_USER:-kb_replicator}',
          MASTER_PASSWORD='${MARIADB_ROOT_PASSWORD}',
          MASTER_USE_GTID=slave_pos,
          MASTER_CONNECT_RETRY=10;
        START SLAVE IO_THREAD;
      " 2>/dev/null; then
        echo "CHANGE MASTER TO or START SLAVE IO_THREAD failed; retrying in 5s"
        sleep 5
        continue
      fi
      # alpha.99: removed prepare_fresh_replica_for_sql_thread_start
      # (see comment block in runtime-secondary-follow-configure
      # above). The function used to DELETE kubeblocks
      # .kb_health_check on local secondary which directly
      # triggered the 1032 cascade documented in cluster
      # mdb-repro-1032 evidence (2026-05-25 08:03Z).
      if ! "${LOCAL[@]}" -e "START SLAVE SQL_THREAD;" 2>/dev/null; then
        # tier=error-recovery: SQL thread start has already failed.
        # mark_replication_pending + best-effort defensive locks +
        # continue retry loop (does NOT publish ready/role).
        mark_replication_pending
        set_fail_closed_read_only "fresh-sql-thread-start-failed" || true # tier=error-recovery
        lock_local_root_writes "fresh-sql-thread-start-failed" || true # tier=error-recovery
        echo "START SLAVE SQL_THREAD failed; keeping roleProbe pending."
        sleep 5
        continue
      fi
    else
      "${LOCAL[@]}" -e "
        STOP SLAVE;
        CHANGE MASTER TO
          MASTER_HOST='${PRIMARY_HOST}',
          MASTER_USER='${MARIADB_REPL_USER:-kb_replicator}',
          MASTER_PASSWORD='${MARIADB_ROOT_PASSWORD}',
          MASTER_USE_GTID=slave_pos,
          MASTER_CONNECT_RETRY=10;
        START SLAVE;
      " 2>/dev/null || true
    fi
    # Step 3: verify CHANGE MASTER TO actually stored config.
    # If it failed (e.g. auth error, primary briefly unreachable), retry from step 1
    # after a short backoff. Only remove .replication-pending once slave config is
    # confirmed. Do NOT self-elect on failure.
    SLAVE_STATUS_CHECK=$("${LOCAL[@]}" -e "SHOW SLAVE STATUS;" 2>/dev/null)
    if [ -n "${SLAVE_STATUS_CHECK}" ]; then
      if publish_replica_after_rejoin_ready "new-slave-config"; then
        echo "Replication configured from primary ${PRIMARY_HOST} at GTID ${MASTER_GTID}"
        break
      fi
      if fail_closed_for_gtid_divergence; then
        wait ${MARIADB_PID}
        exit 1
      fi
      echo "Replication stored but not healthy yet; retrying in 5s"
      sleep 5
      continue
    fi
    echo "CHANGE MASTER TO did not store config; retrying in 5s"
    sleep 5
  done
else
  # Pod-0, primary unreachable, no slave config: start as primary by default.
  # If the primary write gate fails, do not block forever inside the
  # bootstrap branch. Keep the pod fail-closed and let the runtime
  # reconcile loop observe the syncer/DCS decision: if another pod is
  # elected primary, this pod can configure replication and publish
  # secondary only after replica health is real.
  if expose_sql_listener_for_primary_role "default-pod0-primary"; then
    mark_replication_ready
    echo "Starting as primary by default (index=0)"
  else
    mark_replication_pending
    echo "Default pod-0 primary publish failed; entering runtime role reconcile loop"
  fi
fi

# Background: clear the semi-sync ACK receiver deadlock when detected.
# When a secondary is RST-killed, MariaDB's ACK receiver thread can deadlock for
# ~150s (TCP retransmit timeout), blocking ALL new TCP connections to the primary.
# Detection: Unix socket shows clients=0 AND TCP connection to port 3306 fails.
# (Unix socket bypasses TCP; if TCP is blocked, it's the deadlock — not just a
#  transient state where the secondary is reconnecting.)
# Toggling rpl_semi_sync_master_enabled=0→1 stops and restarts the ACK receiver.
SOCK="/run/mysqld/mysqld.sock"
SOCK_CLI=(mariadb "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -S "${SOCK}" -N -s)
TCP_CLI=(mariadb "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -P3306 -h127.0.0.1 -N -s)
(while kill -0 ${MARIADB_PID} 2>/dev/null; do
  sleep 10
  # Deadlock check: Unix socket works even during ACK receiver deadlock;
  # TCP fails when deadlocked. Do NOT gate on clients=0: a force-killed
  # slave leaves a CLOSE-WAIT connection that keeps clients=1, masking the
  # deadlock. Check TCP directly — if it fails, toggle to restart ACK receiver.
  if ! timeout 3 "${TCP_CLI[@]}" -e "SELECT 1;" >/dev/null 2>&1; then
    if kill -0 ${MARIADB_PID} 2>/dev/null; then
      if is_semisync_mode_env; then
        "${SOCK_CLI[@]}" \
          -e "SET GLOBAL rpl_semi_sync_master_enabled=0; SET GLOBAL rpl_semi_sync_master_enabled=1;" \
          2>/dev/null || true
      else
        prestop_watchdog_log "skip-semisync-master-ack-reset label=background-tcp-probe reason=replication-mode-not-semisync mode=${MARIADB_REPLICATION_MODE:-<empty>}"
      fi
    fi
  fi
done) &

# Switchover is coordinated by /scripts/replication-switchover.sh
# through syncerctl, which creates the DCS switchover record. Remove
# stale raw-SQL trigger files from older script versions so they cannot
# race with syncer's HA loop.
rm -f ${DATA_DIR}/.switchover-request \
  ${DATA_DIR}/.switchover-done \
  ${DATA_DIR}/.switchover-error

wait_for_mariadbd_with_role_reconcile
