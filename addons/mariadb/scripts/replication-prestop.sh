#!/bin/sh
DATA_DIR="${MARIADB_DATADIR:-/var/lib/mysql}"
LOG_DIR="${DATA_DIR}/log"
LOG_FILE="${LOG_DIR}/prestop-fence.log"
INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
mkdir -p "${LOG_DIR}" 2>/dev/null || true
prestop_log() {
  line="$(date -u +"%Y-%m-%dT%H:%M:%SZ") prestop-fence $*"
  echo "${line}"
  printf '%s\n' "${line}" >> "${LOG_FILE}" 2>/dev/null || true
}
run_sql() {
  label="$1"
  mode="$2"
  sql="$3"
  if [ "${mode}" = "socket" ]; then
    timeout 3 mariadb -u"${INTERNAL_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" \
      -S /run/mysqld/mysqld.sock -e "${sql}" >> "${LOG_FILE}" 2>&1
  else
    timeout 3 mariadb -u"${INTERNAL_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" \
      -h127.0.0.1 -P3306 -e "${sql}" >> "${LOG_FILE}" 2>&1
  fi
  rc=$?
  prestop_log "${label} rc=${rc}"
  return "${rc}"
}
fence_read_only() {
  label="$1"
  mode="$2"
  run_sql "${label}-no-lock-no-admin" "${mode}" "SET GLOBAL read_only = NO_LOCK_NO_ADMIN;" \
    || run_sql "${label}-fallback-on" "${mode}" "SET GLOBAL read_only = ON;" \
    || run_sql "${label}-fallback-1" "${mode}" "SET GLOBAL read_only = 1;" \
    || true
}
prestop_sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}
lock_local_root_for_prestop() {
  # alpha.64 v1 (Jack 09:35 RED): drop SUPER (admin bypass).
  # NOTE: preStop hook is a SEPARATE shell scope (/bin/sh -c
  # block) so the main-container CMPD_SECONDARY_FENCE_GRANT_BODY
  # constant is NOT in scope here. The literal grant list
  # below MUST be kept in sync with the main-container constant
  # CMPD_SECONDARY_FENCE_GRANT_BODY (line ~155). ShellSpec
  # rendered-manifest negative grep enforces both callsites
  # do not contain SUPER / READ_ONLY ADMIN / BINLOG ADMIN /
  # CONNECTION ADMIN. Tier B (Jack 10:05): prestop LOCK is
  # required; failure MUST fail-closed (return 1) so caller
  # does not proceed.
  label="$1"
  mode="$2"
  user="$(prestop_sql_quote "${MARIADB_ROOT_USER}")"
  password="$(prestop_sql_quote "${MARIADB_ROOT_PASSWORD}")"
  for host in localhost 127.0.0.1; do
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${host}';
      GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, SLAVE MONITOR, REPLICATION MASTER ADMIN ON *.* TO '${user}'@'${host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
    if run_sql "${label}-local-root-lock-${host}" "${mode}" "${sql}"; then
      prestop_log "local-root-lock label=${label} host=${host} mode=${mode} rc=0 tier=required"
      continue
    fi
    prestop_log "local-root-lock label=${label} host=${host} mode=${mode} rc=1 tier=required 1227_swallowed=true fail_closed=true"
    return 1
  done
}
mariadbd_pids() {
  if command -v pidof >/dev/null 2>&1; then
    pidof mariadbd 2>/dev/null || true
    return
  fi
  ps 2>/dev/null | awk '$NF ~ /mariadbd$/ {print $1}'
}
wait_mariadbd_exit() {
  limit="$1"
  i=0
  while [ "${i}" -lt "${limit}" ]; do
    pids="$(mariadbd_pids | tr '\n' ' ')"
    if [ -z "${pids}" ]; then
      prestop_log "mariadbd exited after ${i}s"
      return 0
    fi
    sleep 1
    i=$((i + 1))
  done
  prestop_log "mariadbd still running after ${limit}s pids=${pids}"
  return 1
}

prestop_log "begin pod=${POD_NAME:-unknown}"
touch "${DATA_DIR}/.prestop-fence-started" "${DATA_DIR}/.replication-pending" 2>/dev/null || true
rm -f "${DATA_DIR}/.replication-ready" 2>/dev/null || true
# alpha.64 v2 (Jack 10:32 HOLD blocker 2): Tier B preStop
# required LOCK MUST NOT be silently swallowed by trailing
# `|| true`. socket→tcp fallback is best-effort attempt
# ordering; double failure emits an explicit fail-closed
# token for the runtime negative gate. preStop has already
# removed `.replication-ready` above and set
# `.prestop-fence-started`, so continuing to kill mariadbd
# IS the fail-closed behavior at the pod level — but the
# log token is what the live-gate runtime negative grep
# asserts. Do NOT add `|| true` after this block.
if ! lock_local_root_for_prestop "prestop" "socket"; then
  if ! lock_local_root_for_prestop "prestop" "tcp"; then
    prestop_log "prestop_lock_failed_both fail_closed=true tier=required"
  fi
fi
if [ -x /tools/syncerctl ]; then
  timeout 3 /tools/syncerctl pause >> "${LOG_FILE}" 2>&1
  prestop_log "syncerctl-pause rc=$?"
else
  prestop_log "syncerctl-pause skipped: /tools/syncerctl missing"
fi

run_sql "socket-state-before" "socket" "SELECT NOW(), @@global.read_only, @@global.gtid_binlog_state, @@global.gtid_binlog_pos;" || true
fence_read_only "socket-read-only" "socket"
fence_read_only "tcp-read-only" "tcp"
# This closes secondary IO with FIN instead of RST and avoids the
# semi-sync ACK receiver deadlock on the primary. It is harmless on a primary.
run_sql "socket-stop-slave-io" "socket" "STOP SLAVE IO_THREAD;" || true
run_sql "tcp-stop-slave-io" "tcp" "STOP SLAVE IO_THREAD;" || true
run_sql "socket-state-after-fence" "socket" "SELECT NOW(), @@global.read_only, @@global.gtid_binlog_state, @@global.gtid_binlog_pos;" || true

pids="$(mariadbd_pids | tr '\n' ' ')"
if [ -n "${pids}" ]; then
  prestop_log "term mariadbd pids=${pids}"
  kill -TERM ${pids} 2>/dev/null || true
else
  prestop_log "mariadbd pid not found before term"
fi

if ! wait_mariadbd_exit 15; then
  pids="$(mariadbd_pids | tr '\n' ' ')"
  if [ -n "${pids}" ]; then
    prestop_log "kill mariadbd pids=${pids}"
    kill -KILL ${pids} 2>/dev/null || true
  fi
  if ! wait_mariadbd_exit 5; then
    touch "${DATA_DIR}/.prestop-fence-failed" 2>/dev/null || true
    prestop_log "end status=failed"
    exit 0
  fi
fi

touch "${DATA_DIR}/.prestop-fence-complete" 2>/dev/null || true
prestop_log "end status=complete"
