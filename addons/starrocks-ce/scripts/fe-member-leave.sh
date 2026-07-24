#!/usr/bin/env bash
set -o pipefail

MEMBER_LEAVE_ACTION_TIMEOUT_SECS=50
MEMBER_LEAVE_INTERNAL_DEADLINE_SECS=45
BDB_TRANSFER_TIMEOUT_MILLIS=5000
MYSQL_CONNECT_TIMEOUT_SECS=5
MYSQL_COMMAND_TIMEOUT_SECS="${MYSQL_COMMAND_TIMEOUT_SECS:-6}"
JAVA_COMMAND_TIMEOUT_SECS=7
COMMAND_KILL_GRACE_SECS=1
COMMAND_LAUNCH_GRACE_SECS=1
ACTION_DEADLINE=0

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

redact_secret() {
  local value="$1"
  local secret

  for secret in "${STARROCKS_PASSWORD:-}" "${MYSQL_PWD:-}"; do
    if [ -n "${secret}" ]; then
      value=${value//"${secret}"/<redacted>}
    fi
  done
  value=${value//$'\n'/; }
  printf '%s' "${value}"
}

diagnose_failure() {
  local phase="$1"
  local retry_safe="$2"
  local rc="$3"
  local detail
  detail=$(redact_secret "$4")
  printf 'memberLeave failure phase=%s retry_safe=%s rc=%s detail=%s\n' \
    "${phase}" "${retry_safe}" "${rc}" "${detail}" >&2
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    diagnose_failure "runtime-prerequisite" "false" "127" \
      "required command ${command_name} is unavailable"
    return 1
  fi
}

require_nonempty_input() {
  local name="$1"
  local value="$2"

  if [ -z "${value}" ]; then
    diagnose_failure "required-input" "false" "1" \
      "required input ${name} is unset or empty"
    return 1
  fi
}

validate_required_inputs() {
  require_nonempty_input "KB_LEAVE_MEMBER_POD_NAME" "${KB_LEAVE_MEMBER_POD_NAME:-}" || return 1
  require_nonempty_input "FE_DISCOVERY_SERVICE_NAME" "${FE_DISCOVERY_SERVICE_NAME:-}" || return 1
  require_nonempty_input "STARROCKS_USER" "${STARROCKS_USER:-}" || return 1
}

resolve_bdb_je_jar() {
  if [ -n "${BDB_JE_JAR_PATH:-}" ]; then
    if [ ! -r "${BDB_JE_JAR_PATH}" ]; then
      diagnose_failure "runtime-prerequisite" "false" "1" \
        "BDB JE jar is not readable at configured path"
      return 1
    fi
    return 0
  fi

  set -- /opt/starrocks/fe/lib/starrocks-bdb-je*.jar
  if [ "$#" -ne 1 ] || [ ! -r "$1" ]; then
    diagnose_failure "runtime-prerequisite" "false" "1" \
      "expected exactly one readable StarRocks BDB JE jar"
    return 1
  fi
  BDB_JE_JAR_PATH="$1"
}

validate_nonnegative_integer() {
  local name="$1"
  local value="$2"
  case "${value}" in
    ''|*[!0-9]*)
      diagnose_failure "invalid-time-budget" "false" "2" \
        "${name} must be a non-negative integer"
      return 1
      ;;
  esac
}

validate_time_budget() {
  validate_nonnegative_integer "MYSQL_COMMAND_TIMEOUT_SECS" "${MYSQL_COMMAND_TIMEOUT_SECS}" || return 1

  if [ "${MYSQL_COMMAND_TIMEOUT_SECS}" -eq 0 ]; then
    diagnose_failure "invalid-time-budget" "false" "2" \
      "MYSQL_COMMAND_TIMEOUT_SECS must be greater than zero"
    return 1
  fi
  if [ "${MEMBER_LEAVE_INTERNAL_DEADLINE_SECS}" -ge "${MEMBER_LEAVE_ACTION_TIMEOUT_SECS}" ]; then
    diagnose_failure "invalid-time-budget" "false" "2" \
      "internal action deadline must leave headroom below the kbagent timeout"
    return 1
  fi
}

member_leave_runtime_check() {
  if [ ! -x /bin/bash ]; then
    diagnose_failure "runtime-prerequisite" "false" "127" \
      "/bin/bash is unavailable in the memberLeave action image"
    return 1
  fi
  require_command "mysql" || return 1
  require_command "java" || return 1
  require_command "timeout" || return 1
  resolve_bdb_je_jar || return 1
  validate_time_budget
}

BOUNDED_TIMED_OUT="false"
run_bounded_command() {
  local requested_timeout_secs="$1"
  local stdout_file="$2"
  local stderr_file="$3"
  shift 3
  local rc timeout_secs

  BOUNDED_TIMED_OUT="false"
  bounded_command_budget "${requested_timeout_secs}"
  timeout_secs="${BOUNDED_COMMAND_BUDGET}"
  if [ "${timeout_secs}" -le 0 ]; then
    BOUNDED_TIMED_OUT="true"
    return 124
  fi

  timeout --signal=TERM --kill-after=1 "${timeout_secs}s" "$@" \
    >"${stdout_file}" 2>"${stderr_file}"
  rc=$?
  if [ "${rc}" -eq 124 ] || [ "${rc}" -eq 137 ]; then
    BOUNDED_TIMED_OUT="true"
  fi
  return "${rc}"
}

bounded_command_budget() {
  local requested="$1"
  local remaining=$((ACTION_DEADLINE - SECONDS))
  local command_window=$((remaining - COMMAND_LAUNCH_GRACE_SECS - COMMAND_KILL_GRACE_SECS))

  if [ "${command_window}" -le 0 ]; then
    BOUNDED_COMMAND_BUDGET=0
  elif [ "${requested}" -lt "${command_window}" ]; then
    BOUNDED_COMMAND_BUDGET="${requested}"
  else
    BOUNDED_COMMAND_BUDGET="${command_window}"
  fi
}

MYSQL_OUTPUT=""
run_mysql_query() {
  local phase="$1"
  local host="$2"
  local statement="$3"
  local out_file="${TMPDIR:-/tmp}/starrocks-member-leave-mysql.$$.out"
  local err_file="${TMPDIR:-/tmp}/starrocks-member-leave-mysql.$$.err"
  local rc detail
  local MYSQL_PWD="${MYSQL_PWD:-${STARROCKS_PASSWORD:-}}"
  export MYSQL_PWD

  MYSQL_OUTPUT=""
  if ! : > "${out_file}" || ! : > "${err_file}"; then
    diagnose_failure "runtime-prerequisite" "false" "1" "cannot create mysql stderr capture"
    return 1
  fi

  if run_bounded_command "${MYSQL_COMMAND_TIMEOUT_SECS}" "${out_file}" "${err_file}" \
      mysql --connect-timeout="${MYSQL_CONNECT_TIMEOUT_SECS}" -N -B \
      -h "${host}" -P 9030 -u"${STARROCKS_USER}" -e "${statement}" \
      ; then
    MYSQL_OUTPUT=$(cat "${out_file}" 2>/dev/null)
    rm -f "${out_file}" "${err_file}"
    return 0
  else
    rc=$?
  fi

  if [ "${BOUNDED_TIMED_OUT}" = "true" ]; then
    rm -f "${out_file}" "${err_file}"
    diagnose_failure "${phase}-timeout" "true" "124" \
      "mysql command exceeded its bounded action budget"
    return 124
  fi
  detail=$(cat "${err_file}" 2>/dev/null)
  rm -f "${out_file}" "${err_file}"
  diagnose_failure "${phase}" "false" "${rc}" "${detail:-mysql command failed}"
  return "${rc}"
}

query_frontends() {
  local phase="$1"
  run_mysql_query "${phase}" "${FE_DISCOVERY_SERVICE_NAME}" "SHOW FRONTENDS"
}

LEAVE_HOST=""
LEAVE_PORT=""
LEADER_HOST=""
HELPER_ENDPOINTS=""
CANDIDATE_NAMES=""
FRONTEND_ROW_COUNT=0
TARGET_MATCH_COUNT=0
LEADER_COUNT=0

is_target_host() {
  local host="$1"
  [ "${host}" = "${KB_LEAVE_MEMBER_POD_NAME}" ] || \
    [[ "${host}" == "${KB_LEAVE_MEMBER_POD_NAME}."* ]]
}

parse_frontends() {
  local output="$1"
  local normalized name ip edit_log_port role

  LEAVE_HOST=""
  LEAVE_PORT=""
  LEADER_HOST=""
  HELPER_ENDPOINTS=""
  CANDIDATE_NAMES=""
  FRONTEND_ROW_COUNT=0
  TARGET_MATCH_COUNT=0
  LEADER_COUNT=0

  if ! normalized=$(printf '%s\n' "${output}" | awk -F '\t' '
      BEGIN { OFS="\034" }
      NF != 16 { exit 1 }
      $1 == "" || $2 == "" { exit 1 }
      $3 !~ /^[0-9]+$/ || $4 !~ /^[0-9]+$/ ||
          $5 !~ /^[0-9]+$/ || $6 !~ /^[0-9]+$/ { exit 1 }
      $7 !~ /^(LEADER|FOLLOWER|OBSERVER)$/ || $8 !~ /^[0-9]+$/ { exit 1 }
      $9 !~ /^(true|false)$/ || $10 !~ /^(true|false)$/ ||
          $11 !~ /^[0-9]+$/ || $12 == "" ||
          $13 !~ /^(true|false)$/ || $15 == "" || $16 == "" { exit 1 }
      seen_name[$1]++ || seen_endpoint[$2 SUBSEP $3]++ { exit 1 }
      { print $1, $2, $3, $7 }
    '); then
    diagnose_failure "frontends-snapshot-invalid" "false" "1" \
      "SHOW FRONTENDS did not match the exact 16-column FE contract or contained duplicate identities"
    return 1
  fi
  if [ -z "${normalized}" ]; then
    diagnose_failure "frontends-snapshot-invalid" "false" "1" \
      "SHOW FRONTENDS returned no FE rows"
    return 1
  fi

  while IFS=$'\034' read -r name ip edit_log_port role; do

    FRONTEND_ROW_COUNT=$((FRONTEND_ROW_COUNT + 1))
    if is_target_host "${ip}"; then
      TARGET_MATCH_COUNT=$((TARGET_MATCH_COUNT + 1))
      LEAVE_HOST="${ip}"
      LEAVE_PORT="${edit_log_port}"
    else
      if [ -n "${HELPER_ENDPOINTS}" ]; then
        HELPER_ENDPOINTS="${HELPER_ENDPOINTS},${ip}:${edit_log_port}"
        CANDIDATE_NAMES="${CANDIDATE_NAMES},${name}"
      else
        HELPER_ENDPOINTS="${ip}:${edit_log_port}"
        CANDIDATE_NAMES="${name}"
      fi
    fi
    if [ "${role}" = "LEADER" ]; then
      LEADER_COUNT=$((LEADER_COUNT + 1))
      LEADER_HOST="${ip}"
    fi
  done <<EOF
${normalized}
EOF

  if [ "${LEADER_COUNT}" -gt 1 ]; then
    diagnose_failure "frontends-snapshot-invalid" "false" "1" \
      "SHOW FRONTENDS returned multiple leaders"
    return 1
  fi
  if [ "${TARGET_MATCH_COUNT}" -gt 1 ]; then
    diagnose_failure "frontends-snapshot-invalid" "false" "1" \
      "SHOW FRONTENDS returned multiple rows for the leaving pod identity"
    return 1
  fi
}

exact_member_present() {
  local output="$1"
  local expected_host="$2"
  local expected_port="$3"
  local ip edit_log_port _

  while read -r _ ip edit_log_port _; do
    if [ "${ip}" = "${expected_host}" ] && [ "${edit_log_port}" = "${expected_port}" ]; then
      return 0
    fi
  done <<EOF
${output}
EOF
  return 1
}

run_leader_transfer() {
  local out_file="${TMPDIR:-/tmp}/starrocks-member-leave-java.$$.out"
  local err_file="${TMPDIR:-/tmp}/starrocks-member-leave-java.$$.err"
  local rc detail

  if [ -z "${HELPER_ENDPOINTS}" ] || [ -z "${CANDIDATE_NAMES}" ]; then
    diagnose_failure "leader-transfer-candidates-empty" "false" "1" \
      "no non-leaving FE is available for leader transfer"
    return 1
  fi

  if ! : > "${out_file}" || ! : > "${err_file}"; then
    diagnose_failure "runtime-prerequisite" "false" "1" "cannot create java stderr capture"
    return 1
  fi
  if run_bounded_command "${JAVA_COMMAND_TIMEOUT_SECS}" "${out_file}" "${err_file}" \
      java -jar "${BDB_JE_JAR_PATH}" DbGroupAdmin \
      -helperHosts "${HELPER_ENDPOINTS}" \
      -groupName PALO_JOURNAL_GROUP \
      -transferMaster -force "${CANDIDATE_NAMES}" "${BDB_TRANSFER_TIMEOUT_MILLIS}" \
      ; then
    rm -f "${out_file}" "${err_file}"
    return 0
  else
    rc=$?
  fi

  if [ "${BOUNDED_TIMED_OUT}" = "true" ]; then
    rm -f "${out_file}" "${err_file}"
    diagnose_failure "leader-transfer-timeout" "true" "124" \
      "BDB JE transfer command exceeded its bounded action budget"
    return 124
  fi
  detail=$(cat "${err_file}" 2>/dev/null)
  rm -f "${out_file}" "${err_file}"
  diagnose_failure "leader-transfer-rejected" "false" "${rc}" \
    "${detail:-BDB JE transfer command failed}"
  return "${rc}"
}

wait_for_new_leader() {
  query_frontends "leader-transfer-query" || return 1
  parse_frontends "${MYSQL_OUTPUT}" || return 1

  if [ "${LEADER_COUNT}" -ne 1 ]; then
    diagnose_failure "leader-transfer-not-converged" "true" "1" \
      "leadership has not converged after the transfer attempt"
    return 1
  fi
  if [ -z "${LEAVE_HOST}" ] || [ -z "${LEAVE_PORT}" ]; then
    log "leaving member disappeared while leadership was transferring"
    return 0
  fi
  if ! is_target_host "${LEADER_HOST}"; then
    log "leadership transferred to ${LEADER_HOST}"
    return 0
  fi

  diagnose_failure "leader-transfer-not-converged" "true" "1" \
    "leaving member is still leader after the transfer attempt"
  return 1
}

drop_follower() {
  local host="$1"
  local port="$2"
  local leader="$3"
  run_mysql_query "drop-follower-rejected" "${leader}" \
    "ALTER SYSTEM DROP FOLLOWER '${host}:${port}';"
}

verify_member_absent() {
  local host="$1"
  local port="$2"

  query_frontends "post-drop-query" || return 1
  parse_frontends "${MYSQL_OUTPUT}" || return 1
  if [ "${LEADER_COUNT}" -ne 1 ]; then
    diagnose_failure "leader-not-converged" "true" "1" \
      "SHOW FRONTENDS has no leader after DROP FOLLOWER"
    return 1
  fi
  if [ "${TARGET_MATCH_COUNT}" -eq 0 ] && \
      ! exact_member_present "${MYSQL_OUTPUT}" "${host}" "${port}"; then
    log "membership convergence proved: ${host}:${port} is absent"
    return 0
  fi

  diagnose_failure "post-drop-membership-not-converged" "true" "1" \
    "target identity or exact member ${host}:${port} remains after ALTER rc=0"
  return 1
}

member_leave() {
  local leave_host leave_port

  ACTION_DEADLINE=$((SECONDS + MEMBER_LEAVE_INTERNAL_DEADLINE_SECS))
  validate_required_inputs || return 1
  member_leave_runtime_check || return 1
  query_frontends "query-frontends" || return 1
  parse_frontends "${MYSQL_OUTPUT}" || return 1

  if [ "${LEADER_COUNT}" -ne 1 ]; then
    diagnose_failure "leader-not-converged" "true" "1" \
      "SHOW FRONTENDS has no leader; refusing memberLeave success or DROP FOLLOWER"
    return 1
  fi

  log "leaving member: ${LEAVE_HOST}:${LEAVE_PORT}"
  log "current leader: ${LEADER_HOST}"
  log "helper endpoints: ${HELPER_ENDPOINTS}"
  log "transfer candidates: ${CANDIDATE_NAMES}"

  if [ -z "${LEAVE_HOST}" ] || [ -z "${LEAVE_PORT}" ]; then
    log "leaving member ${KB_LEAVE_MEMBER_POD_NAME} not found in SHOW FRONTENDS; already removed"
    return 0
  fi

  leave_host="${LEAVE_HOST}"
  leave_port="${LEAVE_PORT}"

  if is_target_host "${LEADER_HOST}"; then
    log "leaving member is the current leader; transferring leadership via BDB JE"
    run_leader_transfer || return 1
    wait_for_new_leader || return 1
    if [ -z "${LEAVE_HOST}" ] || [ -z "${LEAVE_PORT}" ]; then
      log "member leave completed for ${KB_LEAVE_MEMBER_POD_NAME}; member already absent"
      return 0
    fi
    leave_host="${LEAVE_HOST}"
    leave_port="${LEAVE_PORT}"
  fi

  log "dropping follower ${leave_host}:${leave_port} from FE cluster via leader ${LEADER_HOST}"
  drop_follower "${leave_host}" "${leave_port}" "${LEADER_HOST}" || return 1
  verify_member_absent "${leave_host}" "${leave_port}" || return 1

  log "member leave completed for ${KB_LEAVE_MEMBER_POD_NAME}"
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  member_leave
fi
