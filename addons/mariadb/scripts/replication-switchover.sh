#!/bin/sh
# Switchover: ask syncer to coordinate ownership via DCS, then wait until
# database truth reflects the new primary and the old primary has followed it.
#
# Env vars set by KubeBlocks:
#   KB_SWITCHOVER_ROLE           - "primary" (only act when we are the primary)
#   KB_SWITCHOVER_CURRENT_NAME   - current primary pod name
#   KB_SWITCHOVER_CANDIDATE_NAME - target replica pod name (may be empty)

DATA_DIR="${MARIADB_DATADIR:-/var/lib/mysql}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
SYNCERCTL_BIN="${SYNCERCTL_BIN:-/tools/syncerctl}"
SYNCERCTL_HOST="${SYNCERCTL_HOST:-127.0.0.1}"
SYNCERCTL_PORT="${SYNCERCTL_PORT:-3601}"
SWITCHOVER_WAIT_SECONDS="${SWITCHOVER_WAIT_SECONDS:-120}"
SWITCHOVER_POLL_SECONDS="${SWITCHOVER_POLL_SECONDS:-2}"
SWITCHOVER_STABILIZATION_SECONDS="${SWITCHOVER_STABILIZATION_SECONDS:-10}"
PRIMARY_SERVICE_ROUTE_WAIT_SECONDS="${PRIMARY_SERVICE_ROUTE_WAIT_SECONDS:-60}"
REMOTE_ROOT_FENCE_WAIT_SECONDS="${REMOTE_ROOT_FENCE_WAIT_SECONDS:-30}"
MARIADB_CONNECT_TIMEOUT_SECONDS="${MARIADB_CONNECT_TIMEOUT_SECONDS:-5}"
MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"
MARIADB_CLIENT_BIN="${MARIADB_CLIENT_BIN:-}"
MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
SWITCHOVER_TRACE_FILE="${SWITCHOVER_TRACE_FILE:-}"

append_switchover_trace() {
  local message="$*"
  local trace_file
  local trace_dir
  trace_file="${SWITCHOVER_TRACE_FILE:-${DATA_DIR}/log/switchover-action.log}"
  trace_dir=$(dirname "${trace_file}" 2>/dev/null || echo "")
  if [ -n "${trace_dir}" ]; then
    mkdir -p "${trace_dir}" 2>/dev/null || true
  fi
  if ! [ -d "${trace_dir}" ] || ! [ -w "${trace_dir}" ]; then
    trace_file="/tmp/switchover-action.log"
    trace_dir="/tmp"
  fi
  printf "%s %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" "${message}" >>"${trace_file}" 2>/dev/null || true
}

log_switchover_info() {
  local message="$*"
  echo "${message}"
  append_switchover_trace "${message}"
}

log_switchover_error() {
  local message="$*"
  echo "${message}" >&2
  append_switchover_trace "${message}"
}

resolve_mariadb_client_bin() {
  if [ -n "${MARIADB_CLIENT_BIN}" ]; then
    if command -v "${MARIADB_CLIENT_BIN}" >/dev/null 2>&1; then
      command -v "${MARIADB_CLIENT_BIN}"
      return 0
    fi
    if [ -x "${MARIADB_CLIENT_BIN}" ]; then
      printf "%s" "${MARIADB_CLIENT_BIN}"
      return 0
    fi
    echo "Switchover failed: MARIADB_CLIENT_BIN=${MARIADB_CLIENT_BIN} is not executable; PATH=${PATH}" >&2
    return 1
  fi

  if [ -x "${MYSQL_CLIENT_DIR}/bin/mariadb" ]; then
    printf "%s" "${MYSQL_CLIENT_DIR}/bin/mariadb"
    return 0
  fi
  if command -v mariadb >/dev/null 2>&1; then
    command -v mariadb
    return 0
  fi

  echo "Switchover failed: mariadb client not found; checked ${MYSQL_CLIENT_DIR}/bin/mariadb and PATH=${PATH}" >&2
  return 1
}

setup_mariadb_client_bin() {
  local resolved
  resolved=$(resolve_mariadb_client_bin) || return 1
  MARIADB_CLIENT_BIN="${resolved}"
  export MARIADB_CLIENT_BIN
  log_switchover_info "Switchover using mariadb client: ${MARIADB_CLIENT_BIN}"
}

resolve_current_name() {
  if [ -n "${KB_SWITCHOVER_CURRENT_NAME}" ]; then
    echo "${KB_SWITCHOVER_CURRENT_NAME}"
    return 0
  fi
  echo "${POD_NAME:-}"
}

resolve_candidate_name() {
  local current_name
  current_name=$(resolve_current_name)
  if [ -n "${KB_SWITCHOVER_CANDIDATE_NAME}" ]; then
    echo "${KB_SWITCHOVER_CANDIDATE_NAME}"
    return 0
  fi

  local current_idx="${current_name##*-}"
  if [ "${current_idx}" = "0" ]; then
    echo "${CLUSTER_NAME}-${COMPONENT_NAME}-1"
  else
    echo "${CLUSTER_NAME}-${COMPONENT_NAME}-0"
  fi
}

resolve_candidate_fqdn() {
  local candidate
  candidate=$(resolve_candidate_name)
  echo "${candidate}.${CLUSTER_NAME}-${COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
}

resolve_primary_service_fqdn() {
  echo "${CLUSTER_NAME}-${COMPONENT_NAME}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
}

query_value() {
  local host="$1"
  local sql="$2"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${host}" -N -s -e "${sql}" 2>/dev/null || echo ""
}

run_sql() {
  local host="$1"
  local sql="$2"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${host}" -N -s -e "${sql}" >/dev/null 2>&1
}

run_local_internal_sql() {
  local sql="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "${sql}" >/dev/null 2>&1
}

run_local_maintenance_sql() {
  local sql="$1"
  run_local_internal_sql "${sql}" || run_sql "127.0.0.1" "${sql}"
}

run_local_sql_best_effort() {
  local sql="$1"
  run_local_maintenance_sql "${sql}" || true
}

query_local_value() {
  local sql="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "${sql}" 2>/dev/null
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

query_slave_status() {
  local host="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${host}" -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}

query_server_id() {
  local host="$1"
  query_value "${host}" "SELECT @@server_id;"
}

has_mariadb_client() {
  [ -x "${MARIADB_CLIENT_BIN}" ] || command -v "${MARIADB_CLIENT_BIN}" >/dev/null 2>&1
}

query_syncer_role() {
  local host="$1"
  "${SYNCERCTL_BIN}" --host "${host}" --port "${SYNCERCTL_PORT}" getrole 2>/dev/null | tr -d '\r\n'
}

remote_root_host_is_local() {
  case "${MARIADB_ROOT_HOST:-%}" in
    localhost|127.0.0.1|::1) return 0 ;;
    *) return 1 ;;
  esac
}

remote_root_has_full_access() {
  local host="$1"
  local user root_host grants
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  root_host=$(sql_quote "${MARIADB_ROOT_HOST:-%}")
  grants=$(query_value "${host}" "SHOW GRANTS FOR '${user}'@'${root_host}';")
  case "${grants}" in
    *"GRANT ALL PRIVILEGES ON *.*"*) return 0 ;;
    *) return 1 ;;
  esac
}

grant_remote_root_optional_admin_privileges_for_secondary() {
  local user root_host privilege sql
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  root_host=$(sql_quote "${MARIADB_ROOT_HOST:-%}")
  for privilege in "REPLICATION SLAVE ADMIN" "REPLICATION MASTER ADMIN" "BINLOG ADMIN" "BINLOG MONITOR" "SLAVE MONITOR" "CONNECTION ADMIN" "READ_ONLY ADMIN"; do
    sql="SET SESSION sql_log_bin=0; GRANT ${privilege} ON *.* TO '${user}'@'${root_host}'; SET SESSION sql_log_bin=1;"
    if run_sql "127.0.0.1" "${sql}"; then
      log_switchover_info "Switchover secondary remote root fence: optional ${privilege} granted for follow/monitoring"
    else
      log_switchover_info "Switchover secondary remote root fence: optional ${privilege} grant skipped or unsupported"
    fi
  done
  run_local_sql_best_effort "FLUSH PRIVILEGES;"
  return 0
}

fence_local_remote_root_for_secondary() {
  local user root_host password sql
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  root_host=$(sql_quote "${MARIADB_ROOT_HOST:-%}")
  password=$(sql_quote "${MARIADB_ROOT_PASSWORD}")
  sql="
    SET SESSION sql_log_bin=0;
    CREATE USER IF NOT EXISTS '${user}'@'${root_host}' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'${root_host}' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'${root_host}' ACCOUNT UNLOCK;
    REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${root_host}';
    GRANT SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN ON *.* TO '${user}'@'${root_host}';
    FLUSH PRIVILEGES;
    SET SESSION sql_log_bin=1;
  "
  run_sql "127.0.0.1" "${sql}" || return 1
  grant_remote_root_optional_admin_privileges_for_secondary || true
  return 0
}

disconnect_local_remote_root_sessions_for_secondary() {
  local user ids id killed=0 skipped=0
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  ids=$(query_local_value "
    SELECT IFNULL(GROUP_CONCAT(ID SEPARATOR ' '), '')
      FROM information_schema.PROCESSLIST
     WHERE USER='${user}'
       AND ID <> CONNECTION_ID()
       AND HOST NOT LIKE 'localhost%'
       AND HOST NOT LIKE '127.0.0.1%'
       AND HOST NOT LIKE '::1%';
  ") || return 1
  if [ -z "${ids}" ]; then
    log_switchover_info "Switchover pre-DCS guard: no active remote root sessions to disconnect"
    return 0
  fi
  log_switchover_info "Switchover pre-DCS guard: disconnecting active remote root sessions ${ids}"
  for id in ${ids}; do
    case "${id}" in
      ''|*[!0-9]*)
        skipped=$((skipped + 1))
        continue
        ;;
    esac
    run_local_sql_best_effort "KILL CONNECTION ${id};"
    killed=$((killed + 1))
  done
  log_switchover_info "Switchover pre-DCS guard: remote root session disconnect issued killed=${killed} skipped=${skipped}"
  return 0
}

local_remote_root_is_fenced_for_secondary() {
  local user root_host grants
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  root_host=$(sql_quote "${MARIADB_ROOT_HOST:-%}")
  grants=$(query_value "127.0.0.1" "SHOW GRANTS FOR '${user}'@'${root_host}';")
  [ -n "${grants}" ] || return 1
  case "${grants}" in
    *"GRANT ALL PRIVILEGES ON *.*"*) return 1 ;;
  esac
  case "${grants}" in
    *"GRANT SELECT"*) return 0 ;;
    *) return 1 ;;
  esac
}

unfence_local_remote_root_for_primary() {
  local user root_host password sql
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  root_host=$(sql_quote "${MARIADB_ROOT_HOST:-%}")
  password=$(sql_quote "${MARIADB_ROOT_PASSWORD}")
  sql="
    SET SESSION sql_log_bin=0;
    CREATE USER IF NOT EXISTS '${user}'@'${root_host}' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'${root_host}' IDENTIFIED BY '${password}';
    ALTER USER '${user}'@'${root_host}' ACCOUNT UNLOCK;
    GRANT ALL PRIVILEGES ON *.* TO '${user}'@'${root_host}' WITH GRANT OPTION;
    FLUSH PRIVILEGES;
    SET SESSION sql_log_bin=1;
  "
  run_sql "127.0.0.1" "${sql}"
}

set_local_read_only() {
  local value="$1"
  run_local_maintenance_sql "SET GLOBAL read_only=${value};"
}

local_read_only_is() {
  local expected="$1"
  local actual
  actual=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  [ "${actual}" = "${expected}" ]
}

rollback_current_primary_switchover_guard() {
  local failed=0
  log_switchover_info "Switchover rollback: restoring current primary write access after pre-DCS failure"
  if ! set_local_read_only "OFF"; then
    log_switchover_error "Switchover rollback failed: could not set current primary read_only=OFF"
    failed=1
  fi
  if ! unfence_local_remote_root_for_primary; then
    log_switchover_error "Switchover rollback failed: could not restore current primary remote root grants"
    failed=1
  fi
  if ! local_read_only_is "0"; then
    log_switchover_error "Switchover rollback failed: current primary read_only did not return to 0"
    failed=1
  fi
  if ! remote_root_has_full_access "127.0.0.1"; then
    log_switchover_error "Switchover rollback failed: current primary remote root grants are not full access"
    failed=1
  fi
  [ "${failed}" -eq 0 ]
}

prepare_current_primary_for_switchover() {
  local current_name
  current_name=$(resolve_current_name)
  log_switchover_info "Switchover pre-DCS guard: fencing remote root on current primary ${current_name}"
  if ! disconnect_local_remote_root_sessions_for_secondary; then
    log_switchover_error "Switchover failed: could not disconnect current primary remote root sessions before fencing"
    rollback_current_primary_switchover_guard || true
    return 1
  fi
  if ! fence_local_remote_root_for_secondary; then
    log_switchover_error "Switchover failed: could not fence current primary remote root before DCS switchover"
    rollback_current_primary_switchover_guard || true
    return 1
  fi
  if ! disconnect_local_remote_root_sessions_for_secondary; then
    log_switchover_error "Switchover failed: could not disconnect current primary remote root sessions after fencing"
    rollback_current_primary_switchover_guard || true
    return 1
  fi
  if ! local_remote_root_is_fenced_for_secondary; then
    log_switchover_error "Switchover failed: current primary remote root fence was not verified before DCS switchover"
    rollback_current_primary_switchover_guard || true
    return 1
  fi
  log_switchover_info "Switchover pre-DCS guard passed for current primary ${current_name}; read_only is left unchanged until syncer accepts the DCS switchover"
  return 0
}

fence_current_primary_local_writes_after_dcs() {
  local current_name
  current_name=$(resolve_current_name)
  log_switchover_info "Switchover post-DCS guard: setting current primary ${current_name} read_only=ON before candidate can accept writes"
  if ! set_local_read_only "ON"; then
    log_switchover_error "Switchover failed: could not set current primary read_only=ON after DCS switchover was accepted"
    return 1
  fi
  if ! local_read_only_is "1"; then
    log_switchover_error "Switchover failed: current primary read_only=ON was not verified after DCS switchover was accepted"
    return 1
  fi
  log_switchover_info "Switchover post-DCS guard passed for current primary ${current_name}"
  return 0
}

syncerctl_switchover() {
  local current_name="$1"
  local candidate_name="$2"
  local output
  local rc

  output=$("${SYNCERCTL_BIN}" --host "${SYNCERCTL_HOST}" --port "${SYNCERCTL_PORT}" \
    switchover --primary "${current_name}" --candidate "${candidate_name}" 2>&1)
  rc=$?
  if [ -n "${output}" ]; then
    log_switchover_info "Switchover syncerctl output: ${output}"
  else
    log_switchover_info "Switchover syncerctl output: <empty>"
  fi
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: syncerctl exited with rc=${rc}"
    return 1
  fi
  case "${output}" in
    *"switchover success"*) return 0 ;;
    *)
      log_switchover_error "Switchover failed: syncerctl did not report success"
      return 1
      ;;
  esac
}

candidate_is_primary() {
  local candidate_fqdn="$1"
  local read_only
  local slave_status

  if ! has_mariadb_client; then
    [ "$(query_syncer_role "${candidate_fqdn}")" = "primary" ]
    return $?
  fi

  read_only=$(query_value "${candidate_fqdn}" "SELECT @@global.read_only;")
  slave_status=$(query_slave_status "${candidate_fqdn}")

  [ "${read_only}" = "0" ] && [ -z "${slave_status}" ] && remote_root_has_full_access "${candidate_fqdn}"
}

slave_status_is_ready_for_candidate() {
  local slave_status="$1"
  local candidate_name="$2"
  local candidate_fqdn="$3"

  [ -n "${slave_status}" ] || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_IO_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_SQL_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_IO_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_SQL_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -F "Master_Host: ${candidate_fqdn}" >/dev/null 2>&1 ||
  printf "%s" "${slave_status}" | grep -F "Master_Host: ${candidate_name}" >/dev/null 2>&1
}

slave_status_has_kb_health_check_repairable_error() {
  local slave_status="$1"
  [ -n "${slave_status}" ] || return 1
  printf "%s" "${slave_status}" | grep -qE "Last_SQL_Errno: 1062|Last_Errno: 1062|Last_SQL_Errno: 1146|Last_Errno: 1146" || return 1
  printf "%s" "${slave_status}" | grep -q "kubeblocks.kb_health_check" || return 1
}

clear_local_kb_health_check_table() {
  local decision="$1"
  if run_local_maintenance_sql "
    SET SESSION sql_log_bin=0;
    CREATE DATABASE IF NOT EXISTS kubeblocks;
    CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check(type INT, check_ts BIGINT, PRIMARY KEY(type));
    DELETE FROM kubeblocks.kb_health_check;
    SET SESSION sql_log_bin=1;
  "; then
    log_switchover_info "Switchover old-primary follow repair: prepared local kubeblocks health check table (${decision})"
    return 0
  fi
  log_switchover_error "Switchover old-primary follow repair: failed to prepare local kubeblocks health check table (${decision})"
  return 1
}

repair_kb_health_check_replication_error() {
  local slave_status="$1"
  if ! slave_status_has_kb_health_check_repairable_error "${slave_status}"; then
    return 1
  fi
  log_switchover_info "Switchover old-primary follow repair: detected repairable kubeblocks health check replication error"
  run_local_sql_best_effort "STOP SLAVE SQL_THREAD;"
  if ! clear_local_kb_health_check_table "prepared-local-kb-health-check-after-switchover-replication-error"; then
    return 1
  fi
  run_local_sql_best_effort "START SLAVE SQL_THREAD;"
  return 0
}

current_follows_candidate() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local read_only
  local slave_status

  if ! has_mariadb_client; then
    [ "$(query_syncer_role "127.0.0.1")" = "secondary" ]
    return $?
  fi

  read_only=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  [ "${read_only}" = "1" ] || return 1

  slave_status=$(query_slave_status "127.0.0.1")
  if slave_status_is_ready_for_candidate "${slave_status}" "${candidate_name}" "${candidate_fqdn}"; then
    return 0
  fi
  if repair_kb_health_check_replication_error "${slave_status}"; then
    slave_status=$(query_slave_status "127.0.0.1")
    slave_status_is_ready_for_candidate "${slave_status}" "${candidate_name}" "${candidate_fqdn}" && return 0
  fi
  return 1
}

primary_service_routes_candidate() {
  local candidate_fqdn="$1"
  local candidate_server_id
  local service_server_id

  candidate_server_id=$(query_server_id "${candidate_fqdn}")
  [ -n "${candidate_server_id}" ] || return 1

  service_server_id=$(query_server_id "$(resolve_primary_service_fqdn)")
  [ "${service_server_id}" = "${candidate_server_id}" ]
}

log_primary_service_route_diagnostic() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local primary_service_fqdn
  local candidate_server_id
  local service_server_id
  local route_status="pending"
  local observation

  primary_service_fqdn=$(resolve_primary_service_fqdn)
  candidate_server_id=$(query_server_id "${candidate_fqdn}")
  service_server_id=$(query_server_id "${primary_service_fqdn}")
  if [ -n "${candidate_server_id}" ] && [ "${service_server_id}" = "${candidate_server_id}" ]; then
    route_status="matched"
  fi
  observation="candidate=${candidate_name} candidate_fqdn=${candidate_fqdn} primary_service=${primary_service_fqdn} expected_server_id=${candidate_server_id:-<empty-or-error>} service_server_id=${service_server_id:-<empty-or-error>} route_status=${route_status}"
  echo "Switchover service-route diagnostic: ${observation}"
  return 0
}

wait_post_switchover_stabilization() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local waited=0

  while [ "${waited}" -lt "${SWITCHOVER_STABILIZATION_SECONDS}" ]; do
    candidate_is_primary "${candidate_fqdn}" || return 1
    current_follows_candidate "${candidate_name}" "${candidate_fqdn}" || return 1
    sleep "${SWITCHOVER_POLL_SECONDS}"
    waited=$((waited + SWITCHOVER_POLL_SECONDS))
  done

  echo "Switchover stabilization window passed for candidate ${candidate_name} using pod/headless DB truth"
  return 0
}

wait_primary_service_routes_candidate() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local waited=0

  while [ "${waited}" -lt "${PRIMARY_SERVICE_ROUTE_WAIT_SECONDS}" ]; do
    if primary_service_routes_candidate "${candidate_fqdn}"; then
      log_primary_service_route_diagnostic "${candidate_name}" "${candidate_fqdn}"
      log_switchover_info "Switchover primary service route converged for candidate ${candidate_name} after ${waited}s"
      return 0
    fi
    log_primary_service_route_diagnostic "${candidate_name}" "${candidate_fqdn}"
    sleep "${SWITCHOVER_POLL_SECONDS}"
    waited=$((waited + SWITCHOVER_POLL_SECONDS))
  done

  log_switchover_error "Switchover timed out: primary service did not route to candidate ${candidate_name} within ${PRIMARY_SERVICE_ROUTE_WAIT_SECONDS}s"
  return 1
}

wait_switchover_done() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local waited=0

  while [ "${waited}" -lt "${SWITCHOVER_WAIT_SECONDS}" ]; do
    if candidate_is_primary "${candidate_fqdn}" && current_follows_candidate "${candidate_name}" "${candidate_fqdn}"; then
      if ! wait_post_switchover_stabilization "${candidate_name}" "${candidate_fqdn}"; then
        log_switchover_error "Switchover timed out: post-switchover stabilization did not hold for candidate ${candidate_name}"
        return 1
      fi
      if ! wait_primary_service_routes_candidate "${candidate_name}" "${candidate_fqdn}"; then
        return 1
      fi
      log_switchover_info "Switchover done: ${candidate_name} is primary and $(resolve_current_name) follows it"
      return 0
    fi
    sleep "${SWITCHOVER_POLL_SECONDS}"
    waited=$((waited + SWITCHOVER_POLL_SECONDS))
  done

  log_switchover_error "Switchover timed out: syncer DCS switchover did not converge for candidate ${candidate_name}"
  return 1
}

wait_current_secondary_remote_root_fenced() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local waited=0

  while [ "${waited}" -lt "${REMOTE_ROOT_FENCE_WAIT_SECONDS}" ]; do
    if current_follows_candidate "${candidate_name}" "${candidate_fqdn}"; then
      if fence_local_remote_root_for_secondary && local_remote_root_is_fenced_for_secondary; then
        log_switchover_info "Switchover secondary remote root fence converged for $(resolve_current_name) after ${waited}s"
        return 0
      fi
    fi
    sleep "${SWITCHOVER_POLL_SECONDS}"
    waited=$((waited + SWITCHOVER_POLL_SECONDS))
  done

  log_switchover_error "Switchover failed: current secondary remote root fence did not converge within ${REMOTE_ROOT_FENCE_WAIT_SECONDS}s"
  return 1
}

run_switchover() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local current_name
  current_name=$(resolve_current_name)

  if [ -z "${current_name}" ]; then
    echo "Switchover failed: current primary name is empty" >&2
    return 1
  fi
  if [ -z "${candidate_name}" ]; then
    echo "Switchover failed: candidate name is empty" >&2
    return 1
  fi

  if ! prepare_current_primary_for_switchover; then
    return 1
  fi

  log_switchover_info "Switchover: creating syncer DCS switchover primary=${current_name} candidate=${candidate_name}"
  if ! syncerctl_switchover "${current_name}" "${candidate_name}"; then
    rollback_current_primary_switchover_guard || true
    log_switchover_error "Switchover failed: syncerctl could not create DCS switchover"
    return 1
  fi
  if ! fence_current_primary_local_writes_after_dcs; then
    log_switchover_error "Switchover failed: current primary local write fence did not close after DCS switchover"
    return 1
  fi

  if ! wait_switchover_done "${candidate_name}" "${candidate_fqdn}"; then
    return 1
  fi
  if ! wait_current_secondary_remote_root_fenced "${candidate_name}" "${candidate_fqdn}"; then
    return 1
  fi
}

main() {
  if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
    echo "Not the primary, nothing to do."
    return 0
  fi
  setup_mariadb_client_bin || return 1

  local candidate_name
  local candidate_fqdn
  candidate_name=$(resolve_candidate_name)
  candidate_fqdn=$(resolve_candidate_fqdn)
  run_switchover "${candidate_name}" "${candidate_fqdn}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

set -e
main
