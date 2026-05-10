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
SWITCHOVER_POLL_SECONDS="${SWITCHOVER_POLL_SECONDS:-1}"
# alpha.59: kbagent enforces maxActionCallTimeout=60s
# (pkg/kbagent/service/action_utils.go). The switchover action is intentionally
# bounded to a small budget; post-DCS convergence (Primary Service endpoint,
# old-primary follow, secondary remote root fence, kb_health_check 1062 repair)
# is delegated to roleProbe + KB endpoint controller. The candidate write probe
# is still synchronous because it is part of the action's success contract:
# action returns 0 only after we have proven the candidate is actually writable.
#
# alpha.61: action now uses a single global deadline rather than per-stage
# fixed sleeps. This avoids the trap where the sum of per-stage sleep budgets
# exceeds the kbagent 60s ceiling under unusual timing. SWITCHOVER_ACTION_DEADLINE_SECONDS
# is the hard contract; per-stage maxima are clamped by the remaining global
# deadline at runtime.
#
# alpha.61 v2 (Jack 02:00 review): POSIX-portable wall clock + 5-stage
# enforcement. The original v1 used bash-only $SECONDS / $'\n' case patterns
# under #!/bin/sh shebang -- in dash $SECONDS is not auto-incrementing, so the
# deadline expression evaluated to 0 forever and the stage loops would only be
# bounded by the kbagent 60s ceiling, defeating the v1 fix. v2 uses
# now_epoch()/initialize_action_clock()/remaining_action_budget()/
# stage_budget_or_exit() helpers built on `date +%s`, `printf|awk`, and
# `command -v timeout`; failures of these primitives are fatal so we never
# silently run with a broken clock or unbounded external calls. Each of the 5
# stages (prepare/dcs/fence/promote/write) checks the remaining global budget
# at entry and emits action_deadline_exhausted_<stage> if exhausted.
SWITCHOVER_ACTION_DEADLINE_SECONDS="${SWITCHOVER_ACTION_DEADLINE_SECONDS:-55}"
SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS="${SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS:-10}"
SWITCHOVER_DCS_STAGE_BUDGET_SECONDS="${SWITCHOVER_DCS_STAGE_BUDGET_SECONDS:-15}"
SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS="${SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS:-15}"
CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS="${CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS:-30}"
CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS="${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS:-10}"
MARIADB_CONNECT_TIMEOUT_SECONDS="${MARIADB_CONNECT_TIMEOUT_SECONDS:-5}"
SYNCERCTL_PER_CALL_TIMEOUT_SECONDS="${SYNCERCTL_PER_CALL_TIMEOUT_SECONDS:-5}"

# Mutable globals set by initialize_action_clock(); consumed by stage helpers.
action_started_epoch=""
SWITCHOVER_HAS_TIMEOUT=""
MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"
MARIADB_CLIENT_BIN="${MARIADB_CLIENT_BIN:-}"
MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
SWITCHOVER_TRACE_FILE="${SWITCHOVER_TRACE_FILE:-}"
SWITCHOVER_REMOTE_ROOT_PROBE_TABLE="${SWITCHOVER_REMOTE_ROOT_PROBE_TABLE:-kubeblocks.kb_root_write_probe}"

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

remote_root_write_ready() {
  local host="$1"
  local label="${2:-candidate-remote-root-write-ready}"
  local table
  remote_root_host_is_local && return 0
  table="${SWITCHOVER_REMOTE_ROOT_PROBE_TABLE}"
  case "${table}" in
    *[!A-Za-z0-9_.]*|*.*.*|.*|*.)
      log_switchover_error "Switchover candidate remote root write probe: invalid table ${table}"
      return 1
      ;;
  esac
  if run_sql "${host}" "
    CREATE DATABASE IF NOT EXISTS kubeblocks;
    CREATE TABLE IF NOT EXISTS ${table}(probe_id VARCHAR(128) PRIMARY KEY, check_ts BIGINT);
    INSERT INTO ${table}(probe_id, check_ts)
      VALUES ('switchover_remote_root_probe', UNIX_TIMESTAMP())
      ON DUPLICATE KEY UPDATE check_ts=VALUES(check_ts);
    DELETE FROM ${table} WHERE probe_id='switchover_remote_root_probe';
  "; then
    log_switchover_info "Switchover candidate remote root write probe label=${label} host=${host} rc=0"
    return 0
  fi
  log_switchover_error "Switchover candidate remote root write probe label=${label} host=${host} rc=1"
  return 1
}

syncer_role_is() {
  local host="$1"
  local expected="$2"
  local role
  [ -x "${SYNCERCTL_BIN}" ] || command -v "${SYNCERCTL_BIN}" >/dev/null 2>&1 || return 1
  role="$(query_syncer_role "${host}")"
  [ "${role}" = "${expected}" ]
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
  # alpha.60 v2 (Jack 23:52 review point 2): rollback path must NOT re-grant
  # admin bypass privileges (READ_ONLY ADMIN / SUPER / BINLOG ADMIN) to user-
  # facing root. Grant the same explicit non-bypass privilege list that the
  # roleProbe primary path uses, so a future switchover's post-DCS fence still
  # works after rollback. GRANT OPTION is in the trailing WITH clause only.
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
    GRANT SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER, CREATE USER ON *.* TO '${user}'@'${root_host}' WITH GRANT OPTION;
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

revoke_user_facing_root_admin_privileges_for_secondary() {
  # alpha.60 v2 hard contract (Jack 23:52 v2 blocker review):
  # Each bypass privilege MUST be revoked individually so 1141 on one cannot
  # mask the continued presence of others. After all per-privilege REVOKEs for
  # a host, we re-issue SHOW GRANTS and assert no bypass privilege remains;
  # if one does, this host is fail-closed (`revoke_residual_bypass`). 1141
  # on a single privilege only marks THAT privilege already-fenced - never
  # the host as a whole.
  #
  # post-DCS read_only=ON does not fence user-facing root that holds
  # READ_ONLY ADMIN / SUPER / BINLOG ADMIN. kb_internal_root is intentionally
  # OUT of scope (it must keep READ_ONLY ADMIN for secondary-side 1062 repair
  # in the alpha.59 secondary roleProbe path).
  local root_user="${MARIADB_ROOT_USER:-root}"
  local hosts host grants out rc
  local total_revoked=0 total_already_fenced=0 total_failed_hosts=0
  local snapshot
  local PRIVS="READ_ONLY ADMIN|SUPER|BINLOG ADMIN"
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  # alpha.60 v3 (Jack 00:08 review): the host enumeration query MUST distinguish
  # "rc=0 with empty stdout" (genuinely no root account) from "rc!=0" (query
  # itself failed for permission/connection/SQL reasons). Treating both as
  # `root_account_not_found` is a class 1 silent fallback that lets the
  # function pretend coverage. If the enumeration fails, fail-closed.
  hosts=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -B -s -e "SELECT Host FROM mysql.user WHERE User='${root_user}';" 2>&1)
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke: reason=root_host_query_failed user=${root_user} rc=${rc} stderr=${hosts}; fail-closed"
    return 1
  fi
  if [ -z "${hosts}" ]; then
    log_switchover_info "Switchover post-DCS root revoke: reason=root_account_not_found user=${root_user} skip (rc=0)"
    return 0
  fi
  while IFS= read -r host; do
    [ -z "${host}" ] && continue
    local host_failed=0 host_revoked=0 host_already=0
    grants=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR '${root_user}'@'${host}';" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      case "${grants}" in
        *1141*|*"no such grant"*|*"There is no such grant"*)
          log_switchover_info "Switchover post-DCS root revoke: reason=privilege_absent_already_fenced ${root_user}@${host} (1141 from SHOW GRANTS)"
          total_already_fenced=$((total_already_fenced + 1))
          continue
          ;;
        *)
          log_switchover_error "Switchover failed: post-DCS root revoke: reason=show_grants_failed ${root_user}@${host} rc=${rc} out=${grants}"
          total_failed_hosts=$((total_failed_hosts + 1))
          continue
          ;;
      esac
    fi
    # Per-privilege REVOKE. 1141 on one priv is local-skip, NEVER host-wide.
    local priv
    for priv in "READ_ONLY ADMIN" "SUPER" "BINLOG ADMIN"; do
      out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
        --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
        -P3306 -h127.0.0.1 -N -s -e "
          SET SESSION sql_log_bin=0;
          REVOKE ${priv} ON *.* FROM '${root_user}'@'${host}';
          SET SESSION sql_log_bin=1;
        " 2>&1)
      rc=$?
      if [ "${rc}" -eq 0 ]; then
        log_switchover_info "Switchover post-DCS root revoke: reason=revoked ${root_user}@${host} priv=${priv}"
        host_revoked=$((host_revoked + 1))
      else
        case "${out}" in
          *1141*|*"no such grant"*|*"There is no such grant"*)
            log_switchover_info "Switchover post-DCS root revoke: reason=privilege_absent_already_fenced ${root_user}@${host} priv=${priv} (1141 on REVOKE)"
            host_already=$((host_already + 1))
            ;;
          *)
            log_switchover_error "Switchover failed: post-DCS root revoke: reason=revoke_failed ${root_user}@${host} priv=${priv} rc=${rc} out=${out}"
            host_failed=$((host_failed + 1))
            ;;
        esac
      fi
    done
    # Per-host post-revoke residual check. If any bypass priv survived,
    # the host is fail-closed regardless of per-priv counts.
    grants=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR '${root_user}'@'${host}';" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      case "${grants}" in
        *1141*|*"no such grant"*|*"There is no such grant"*)
          log_switchover_info "Switchover post-DCS root revoke: reason=privilege_absent_already_fenced ${root_user}@${host} (post-revoke SHOW GRANTS 1141)"
          ;;
        *)
          log_switchover_error "Switchover failed: post-DCS root revoke: reason=post_revoke_show_grants_failed ${root_user}@${host} rc=${rc} out=${grants}"
          host_failed=$((host_failed + 1))
          ;;
      esac
    else
      case "${grants}" in
        *"READ_ONLY ADMIN"*|*"SUPER"*|*"BINLOG ADMIN"*|*"GRANT ALL PRIVILEGES"*|*"ALL PRIVILEGES ON \\*.\\*"*|*"ALL PRIVILEGES ON *.*"*)
          log_switchover_error "Switchover failed: post-DCS root revoke: reason=revoke_residual_bypass ${root_user}@${host} grants=${grants}"
          host_failed=$((host_failed + 1))
          ;;
      esac
    fi
    if [ "${host_failed}" -gt 0 ]; then
      total_failed_hosts=$((total_failed_hosts + 1))
    fi
    total_revoked=$((total_revoked + host_revoked))
    total_already_fenced=$((total_already_fenced + host_already))
  done <<EOF_HOSTS
${hosts}
EOF_HOSTS
  if [ "${total_failed_hosts}" -gt 0 ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke summary revoked=${total_revoked} already_fenced=${total_already_fenced} failed_hosts=${total_failed_hosts}; fail-closed"
    return 1
  fi
  out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "FLUSH PRIVILEGES;" 2>&1)
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke: FLUSH PRIVILEGES failed rc=${rc} out=${out}; fail-closed"
    return 1
  fi
  snapshot=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -B -s -e "
      SELECT CONCAT('user=', User, '@', Host) FROM mysql.user WHERE User='${root_user}';
    " 2>/dev/null | tr '\n' ' ' || true)
  log_switchover_info "Switchover post-DCS root revoke summary revoked=${total_revoked} already_fenced=${total_already_fenced} failed_hosts=0; snapshot=[${snapshot}]"
  return 0
}

verify_post_dcs_local_root_write_fenced() {
  # alpha.59 design-contract close-out: setting @@global.read_only=ON is not
  # enough on its own. Per Jack 19:45 review, the action must also prove that
  # a user-facing root INSERT against this pod's localhost is actually rejected
  # by the read-only fence (server error 1290 or "read-only" message). This
  # closes the "non-empty contract field unenforced at write site" hole that
  # the alpha.58 contract had: alpha.58 only set the marker without ever
  # observing a denied write.
  local out rc
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: post-DCS local-root write fence verification cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "
      SET SESSION sql_log_bin=0;
      CREATE DATABASE IF NOT EXISTS kubeblocks;
      CREATE TABLE IF NOT EXISTS kubeblocks.kb_post_dcs_fence_probe(probe_id VARCHAR(64) PRIMARY KEY, ts BIGINT);
      INSERT INTO kubeblocks.kb_post_dcs_fence_probe(probe_id, ts) VALUES ('post_dcs_fence', UNIX_TIMESTAMP());
    " 2>&1)
  rc=$?
  if [ "${rc}" -eq 0 ]; then
    log_switchover_error "Switchover failed: post-DCS local-root write fence not enforced; user-facing root INSERT succeeded after read_only=ON"
    return 1
  fi
  case "${out}" in
    *1290*|*read-only*|*"read only"*|*"--read-only"*)
      log_switchover_info "Switchover post-DCS local-root write fence verified: user-facing root INSERT rejected (rc=${rc})"
      return 0
      ;;
  esac
  log_switchover_error "Switchover failed: post-DCS local-root write fence verification got unexpected error rc=${rc} out=${out}"
  return 1
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
  # alpha.60: synchronously revoke user-facing root admin bypass privileges
  # (READ_ONLY ADMIN / SUPER / BINLOG ADMIN) for every root account in
  # mysql.user. read_only=ON alone does not fence root that holds these
  # privileges; the alpha.59 verify_post_dcs_local_root_write_fenced caught
  # this gap. Restoration of secondary follow-time grants stays in roleProbe
  # secondary path - this action does NOT re-grant admin bypass.
  if ! revoke_user_facing_root_admin_privileges_for_secondary; then
    return 1
  fi
  if ! verify_post_dcs_local_root_write_fenced; then
    return 1
  fi
  log_switchover_info "Switchover post-DCS guard passed for current primary ${current_name}: read_only=1 + user-facing root admin bypass revoked + local INSERT fenced (1290)"
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

  [ "${read_only}" = "0" ] || return 1
  [ -z "${slave_status}" ] || return 1
  remote_root_has_full_access "${candidate_fqdn}" || return 1
  remote_root_write_ready "${candidate_fqdn}" "candidate-primary" || return 1
  syncer_role_is "${candidate_fqdn}" "primary"
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
  local old_read_only
  if ! slave_status_has_kb_health_check_repairable_error "${slave_status}"; then
    return 1
  fi
  log_switchover_info "Switchover old-primary follow repair: detected repairable kubeblocks health check replication error"
  run_local_sql_best_effort "STOP SLAVE SQL_THREAD;"
  old_read_only=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  case "${old_read_only}" in
    0)
      ;;
    *)
      if ! set_local_read_only "OFF"; then
        log_switchover_error "Switchover old-primary follow repair: failed to temporarily open local read_only for health check repair"
        return 1
      fi
      ;;
  esac
  if ! clear_local_kb_health_check_table "prepared-local-kb-health-check-after-switchover-replication-error"; then
    case "${old_read_only}" in
      0) ;;
      *) set_local_read_only "ON" || true ;;
    esac
    return 1
  fi
  case "${old_read_only}" in
    0)
      ;;
    *)
      if ! set_local_read_only "ON"; then
        log_switchover_error "Switchover old-primary follow repair: failed to restore local read_only after health check repair"
        return 1
      fi
      ;;
  esac
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
  syncer_role_is "127.0.0.1" "secondary" || return 1

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

now_epoch() {
  # POSIX wall-clock seconds. Returns rc=2 (NOT 0 with empty output) on date
  # failure or non-numeric output so callers can distinguish "0 seconds since
  # action start" from "clock unavailable". rc=2 propagates as fail-closed.
  local ts
  ts=$(date +%s 2>/dev/null) || return 2
  case "${ts}" in
    ''|*[!0-9]*) return 2 ;;
  esac
  printf '%s' "${ts}"
}

initialize_action_clock() {
  # Called once at run_switchover entry. Captures the action start epoch and
  # probes for `timeout(1)`. If the wall clock cannot be read OR `timeout` is
  # absent, fail closed BEFORE we touch DCS so we never run with a silently
  # broken clock or an unbounded external call.
  local now
  now=$(now_epoch)
  if [ -z "${now}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable cause=date_failed; fail-closed"
    return 1
  fi
  action_started_epoch="${now}"
  if command -v timeout >/dev/null 2>&1; then
    SWITCHOVER_HAS_TIMEOUT=1
  else
    SWITCHOVER_HAS_TIMEOUT=0
  fi
  return 0
}

remaining_action_budget() {
  # Echo the integer remaining budget in seconds (may be 0 or negative).
  # Returns 2 on clock failure -- caller MUST treat as fail-closed, never as
  # "0 seconds remaining" silent fallback (Jack 02:00 review #1).
  local now
  now=$(now_epoch)
  if [ -z "${now}" ]; then
    printf '0'
    return 2
  fi
  case "${action_started_epoch}" in
    ''|*[!0-9]*) printf '0'; return 2 ;;
  esac
  local elapsed=$(( now - action_started_epoch ))
  local remaining=$(( SWITCHOVER_ACTION_DEADLINE_SECONDS - elapsed ))
  printf '%s' "${remaining}"
  return 0
}

action_elapsed_seconds() {
  # Best-effort elapsed seconds for log messages. Returns "?" on clock failure
  # so logs stay informative even when the deadline path itself failed closed.
  local now
  now=$(now_epoch)
  if [ -z "${now}" ] || [ -z "${action_started_epoch}" ]; then
    printf '?'
    return 0
  fi
  printf '%s' "$(( now - action_started_epoch ))"
}

stage_budget_or_exit() {
  # Compute min(stage_max, remaining_global). On clock failure or
  # remaining<=0, log fail-closed with reason=action_deadline_exhausted_<stage>
  # and return 1 so the caller exits before invoking the stage body. On
  # success, prints the chosen budget so the caller can capture it.
  local stage_name="$1"
  local stage_max="$2"
  local remaining
  remaining=$(remaining_action_budget)
  local rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_${stage_name} cause=action_clock_unavailable elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed"
    return 1
  fi
  if [ "${remaining}" -le 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_${stage_name} elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed"
    return 1
  fi
  local budget="${stage_max}"
  if [ "${remaining}" -lt "${budget}" ]; then
    budget="${remaining}"
  fi
  printf '%s' "${budget}"
  return 0
}

extract_syncerctl_role() {
  # Read syncerctl getrole output and return the role token if present.
  # Looks for a line that, after trimming, equals exactly "primary" or
  # "secondary". Echoes empty string if no match. POSIX-safe: no $'\n'
  # case patterns, no bashism (Jack 02:00 review #1).
  local out="$1"
  printf '%s\n' "${out}" | awk '
    { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "");
      if ($0 == "primary" || $0 == "secondary") { print $0; exit } }
  '
}

run_syncerctl_getrole_with_timeout() {
  # Wrap syncerctl getrole with `timeout <wall>` where wall=min(per_call,
  # stage_budget). Caller MUST verify SWITCHOVER_HAS_TIMEOUT=1 before invoking
  # this (we don't silently fall back to an unbounded call).
  local fqdn="$1"
  local stage_budget="$2"
  local wall="${SYNCERCTL_PER_CALL_TIMEOUT_SECONDS}"
  if [ "${stage_budget}" -lt "${wall}" ]; then
    wall="${stage_budget}"
  fi
  if [ "${wall}" -lt 1 ]; then
    wall=1
  fi
  timeout "${wall}" "${SYNCERCTL_BIN}" --host "${fqdn}" --port "${SYNCERCTL_PORT}" getrole 2>&1
}

wait_candidate_promoted_via_syncerctl() {
  # alpha.61 (Jack 01:40 review): before testing candidate writability, the
  # action MUST observe that DCS has actually promoted the candidate (i.e.,
  # syncerctl getrole on the candidate FQDN returns "primary"). alpha.59
  # accidentally hid the missing-promotion case because user-facing root held
  # READ_ONLY ADMIN and could INSERT through `read_only=1`. After alpha.60's
  # revoke, root cannot bypass; we must wait for actual promotion.
  #
  # Sentinels per Jack class 4: role_unknown (empty/unrecognized output),
  # role_query_failed (rc!=0 + stderr captured), role_not_primary (e.g. still
  # secondary), candidate_fqdn_not_found (DNS / pod missing). Stage budget is
  # clamped by the caller-provided remaining deadline so we never overshoot
  # the global 55s action ceiling.
  #
  # alpha.61 v2 (Jack 02:00 review): replaced bash-only $SECONDS with POSIX
  # now_epoch(); replaced $'\n' case patterns with extract_syncerctl_role()
  # awk parser; required SWITCHOVER_HAS_TIMEOUT=1 so syncerctl can never block
  # longer than min(per_call, stage_budget) seconds.
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local stage_deadline="${3:-${CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS}}"

  if [ -z "${candidate_fqdn}" ]; then
    log_switchover_error "Switchover failed: reason=candidate_fqdn_not_found candidate=${candidate_name}; fail-closed"
    return 1
  fi
  if [ "${SWITCHOVER_HAS_TIMEOUT}" != "1" ]; then
    log_switchover_error "Switchover failed: reason=external_timeout_unavailable stage=candidate_promoted; fail-closed"
    return 1
  fi
  local stage_started_epoch
  stage_started_epoch=$(now_epoch)
  if [ -z "${stage_started_epoch}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_promoted; fail-closed"
    return 1
  fi

  local attempt=0 last_role="" last_rc="" last_stderr=""
  local stage_elapsed=0
  while :; do
    local now
    now=$(now_epoch)
    if [ -z "${now}" ]; then
      log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_promoted; fail-closed"
      return 1
    fi
    stage_elapsed=$(( now - stage_started_epoch ))
    if [ "${stage_elapsed}" -ge "${stage_deadline}" ]; then
      break
    fi
    attempt=$((attempt + 1))
    local per_call_remaining=$(( stage_deadline - stage_elapsed ))
    last_stderr=$(run_syncerctl_getrole_with_timeout "${candidate_fqdn}" "${per_call_remaining}")
    last_rc=$?
    last_role=$(extract_syncerctl_role "${last_stderr}")
    if [ "${last_rc}" -eq 0 ] && [ "${last_role}" = "primary" ]; then
      log_switchover_info "Switchover candidate promoted via DCS observed: candidate=${candidate_name} attempt=${attempt} role=primary rc=0 elapsed=${stage_elapsed}s"
      return 0
    fi
    if [ "${last_rc}" -ne 0 ]; then
      log_switchover_info "Switchover candidate promotion poll attempt=${attempt} reason=role_query_failed rc=${last_rc} stderr=${last_stderr}"
    elif [ -z "${last_role}" ]; then
      log_switchover_info "Switchover candidate promotion poll attempt=${attempt} reason=role_unknown rc=0 stderr=${last_stderr}"
    else
      log_switchover_info "Switchover candidate promotion poll attempt=${attempt} reason=role_not_primary role=${last_role} rc=0"
    fi
    sleep "${SWITCHOVER_POLL_SECONDS}"
  done
  log_switchover_error "Switchover failed: reason=candidate_not_promoted_via_dcs_in_budget candidate=${candidate_name} attempts=${attempt} stage_budget=${stage_deadline}s last_role=${last_role:-<empty>} last_rc=${last_rc} last_stderr=${last_stderr}; fail-closed"
  return 1
}

wait_candidate_remote_root_write_ready() {
  # alpha.59: bounded synchronous probe of the candidate's writability. After
  # alpha.61's wait_candidate_promoted_via_syncerctl precondition, this probe
  # should converge in 1-2s under healthy conditions; the budget is kept
  # because actual SQL write semantics may lag slightly even after syncerctl
  # role flip. SQL stderr is now captured per attempt (Jack 01:40 review)
  # so a non-rc=0 outcome can be attributed (probe_sql_stderr_<errno> /
  # probe_connection_failed) instead of opaque rc=1.
  #
  # alpha.61 v2 (Jack 02:00 review): replaced bash-only $SECONDS with POSIX
  # now_epoch(); SQL probe inherits MARIADB_CONNECT_TIMEOUT_SECONDS and the
  # stage budget bound through this polling loop. Clock failure mid-loop is
  # fail-closed (no silent fallback).
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local stage_deadline="${3:-${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS}}"

  local stage_started_epoch
  stage_started_epoch=$(now_epoch)
  if [ -z "${stage_started_epoch}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_write_probe; fail-closed"
    return 1
  fi

  local attempt=0 last_out="" last_rc=""
  local stage_elapsed=0
  while :; do
    local now
    now=$(now_epoch)
    if [ -z "${now}" ]; then
      log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_write_probe; fail-closed"
      return 1
    fi
    stage_elapsed=$(( now - stage_started_epoch ))
    if [ "${stage_elapsed}" -ge "${stage_deadline}" ]; then
      break
    fi
    attempt=$((attempt + 1))
    if remote_root_write_ready "${candidate_fqdn}" "candidate-remote-root-write-ready"; then
      log_switchover_info "Switchover candidate remote root write probe converged for ${candidate_name} attempt=${attempt} elapsed=${stage_elapsed}s"
      return 0
    fi
    # Capture stderr explicitly for attribution: rerun the same probe SQL
    # with stderr collected so closeout sees the actual SQL error rather
    # than opaque rc=1.
    last_out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h"${candidate_fqdn}" -N -s -e "
        CREATE DATABASE IF NOT EXISTS kubeblocks;
        CREATE TABLE IF NOT EXISTS ${SWITCHOVER_REMOTE_ROOT_PROBE_TABLE}(probe_id VARCHAR(128) PRIMARY KEY, check_ts BIGINT);
        INSERT INTO ${SWITCHOVER_REMOTE_ROOT_PROBE_TABLE}(probe_id, check_ts)
          VALUES ('switchover_remote_root_probe', UNIX_TIMESTAMP())
          ON DUPLICATE KEY UPDATE check_ts=VALUES(check_ts);
        DELETE FROM ${SWITCHOVER_REMOTE_ROOT_PROBE_TABLE} WHERE probe_id='switchover_remote_root_probe';
      " 2>&1)
    last_rc=$?
    log_switchover_info "Switchover candidate remote root write probe attempt=${attempt} rc=${last_rc} stderr=${last_out}"
    sleep "${SWITCHOVER_POLL_SECONDS}"
  done

  log_switchover_error "Switchover failed: reason=candidate_remote_root_write_not_ready_in_budget candidate=${candidate_name} attempts=${attempt} stage_budget=${stage_deadline}s last_rc=${last_rc} last_stderr=${last_out}; fail-closed"
  return 1
}

run_switchover() {
  # alpha.61 v2 contract (Jack 02:00 review): POSIX wall clock + 5-stage
  # deadline enforcement. Each stage entry checks the remaining global budget
  # FIRST via stage_budget_or_exit; if exhausted (or wall clock fails), emits
  # action_deadline_exhausted_<stage> and returns 1 BEFORE invoking the stage
  # body. Stage budget = min(stage_max, remaining_global_budget).
  #
  # Stages (each with its own action_deadline_exhausted_<stage> sentinel):
  #   1. prepare       - prepare_current_primary_for_switchover
  #   2. dcs           - syncerctl_switchover (DCS record)
  #   3. fence         - fence_current_primary_local_writes_after_dcs
  #                      (revoke admin-bypass + verify_post_dcs_local_root_write_fenced)
  #   4. promote       - wait_candidate_promoted_via_syncerctl
  #   5. write         - wait_candidate_remote_root_write_ready
  #
  # External tools that can block:
  #   - syncerctl getrole: wrapped with timeout(1) (initialize_action_clock
  #     verifies command existence; absence of `timeout` fails the action).
  #   - mariadb client SQL probes: bounded by --connect-timeout=
  #     ${MARIADB_CONNECT_TIMEOUT_SECONDS} on connect, and by stage budget
  #     on the polling loop (so cumulative wall time per stage is bounded).
  #
  # Post-DCS convergence (Primary Service endpoint route, old-primary follow,
  # secondary fence, kb_health_check 1062 repair) is delegated to roleProbe
  # + KB endpoint controller; runner side has its own bounded post-OpsRequest
  # gate.
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

  if ! initialize_action_clock; then
    return 1
  fi
  log_switchover_info "Switchover action global deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; per-stage budgets clamped by remaining wall-clock time. has_timeout=${SWITCHOVER_HAS_TIMEOUT}"

  # Stage 1: prepare
  local prepare_budget
  prepare_budget=$(stage_budget_or_exit "prepare" "${SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS}") || return 1
  log_switchover_info "Switchover stage prepare budget=${prepare_budget}s remaining_before=$(remaining_action_budget)s"
  if ! prepare_current_primary_for_switchover; then
    return 1
  fi

  # Stage 2: DCS switchover
  local dcs_budget
  dcs_budget=$(stage_budget_or_exit "dcs" "${SWITCHOVER_DCS_STAGE_BUDGET_SECONDS}") || return 1
  log_switchover_info "Switchover stage dcs budget=${dcs_budget}s remaining_before=$(remaining_action_budget)s primary=${current_name} candidate=${candidate_name}"
  log_switchover_info "Switchover: creating syncer DCS switchover primary=${current_name} candidate=${candidate_name}"
  if ! syncerctl_switchover "${current_name}" "${candidate_name}"; then
    rollback_current_primary_switchover_guard || true
    log_switchover_error "Switchover failed: syncerctl could not create DCS switchover"
    return 1
  fi

  # Stage 3: fence current primary local writes (revoke + verify)
  local fence_budget
  fence_budget=$(stage_budget_or_exit "fence" "${SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS}") || return 1
  log_switchover_info "Switchover stage fence budget=${fence_budget}s remaining_before=$(remaining_action_budget)s"
  if ! fence_current_primary_local_writes_after_dcs; then
    log_switchover_error "Switchover failed: current primary local write fence did not close after DCS switchover"
    return 1
  fi

  # Stage 4: candidate promoted via syncerctl
  local promoted_budget
  promoted_budget=$(stage_budget_or_exit "promote" "${CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS}") || return 1
  log_switchover_info "Switchover stage candidate_promoted budget=${promoted_budget}s remaining_before=$(remaining_action_budget)s"
  if ! wait_candidate_promoted_via_syncerctl "${candidate_name}" "${candidate_fqdn}" "${promoted_budget}"; then
    return 1
  fi

  # Stage 5: candidate remote root write probe
  local write_budget
  write_budget=$(stage_budget_or_exit "write" "${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS}") || return 1
  log_switchover_info "Switchover stage candidate_write_probe budget=${write_budget}s remaining_before=$(remaining_action_budget)s"
  if ! wait_candidate_remote_root_write_ready "${candidate_name}" "${candidate_fqdn}" "${write_budget}"; then
    return 1
  fi

  log_switchover_info "Switchover action returned: DCS recorded, current primary fenced, candidate promoted via DCS, candidate writable. Total elapsed=$(action_elapsed_seconds)s of ${SWITCHOVER_ACTION_DEADLINE_SECONDS}s deadline. Post-DCS convergence delegated to roleProbe + KB endpoint controller."
  return 0
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
