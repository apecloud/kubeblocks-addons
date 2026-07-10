#!/bin/bash
# Logging functions
mysql_log() {
  local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
  printf '%s\n'  "$text"
}
mysql_note() {
  mysql_log "$@"
}
mysql_warn() {
  mysql_log "$@" >&2
}
mysql_error() {
  mysql_log "$@" >&2
  exit 1
}

switchover_diagnose_not_ready() {
  local phase="$1"
  local ctx="$2"
  local retry_safe="$3"
  {
    echo "orc switchover diagnosis:"
    echo "  action: switchover"
    echo "  phase: ${phase}"
    echo "  current: ${KB_SWITCHOVER_CURRENT_NAME:-<unset>}"
    echo "  candidate: ${KB_SWITCHOVER_CANDIDATE_NAME:-<unset>}"
    echo "${ctx}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

run_command_with_budget() {
  local budget="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout "${budget}s" "$@"
    return $?
  fi

  local temp_dir output_file timeout_file pid timer_pid rc
  temp_dir=$(mktemp -d /tmp/orc-switchover.XXXXXX) || return 1
  output_file="${temp_dir}/output"
  timeout_file="${temp_dir}/timeout"
  "$@" > "${output_file}" 2>&1 &
  pid=$!
  (
    sleep "${budget}"
    if kill -0 "${pid}" 2>/dev/null; then
      printf 'timeout\n' > "${timeout_file}"
      kill "${pid}" 2>/dev/null || true
      sleep 1
      kill -9 "${pid}" 2>/dev/null || true
    fi
  ) &
  timer_pid=$!

  wait "${pid}" 2>/dev/null
  rc=$?
  kill "${timer_pid}" 2>/dev/null || true
  wait "${timer_pid}" 2>/dev/null || true
  cat "${output_file}"
  if [ -s "${timeout_file}" ]; then
    rc=124
  fi
  rm -rf "${temp_dir}"
  return $rc
}

run_orchestrator_client_with_budget() {
  local budget="$1"
  shift
  run_command_with_budget "${budget}" /kubeblocks/orchestrator-client "$@"
}

ORC_SWITCHOVER_CLIENT_PID=""
ORC_SWITCHOVER_CLIENT_OUTPUT_FILE=""
ORC_SWITCHOVER_CLIENT_RC_FILE=""
ORC_SWITCHOVER_CLIENT_TEMP_DIR=""
ORC_SWITCHOVER_CLIENT_RC=""
ORC_SWITCHOVER_CLIENT_OUTPUT=""
SWITCHOVER_VERIFY_CANDIDATE_RAW=""
SWITCHOVER_VERIFY_CURRENT_RAW=""

start_orchestrator_client_background() {
  local budget="$1"
  shift
  if ! ORC_SWITCHOVER_CLIENT_TEMP_DIR=$(mktemp -d /tmp/orc-switchover-client.XXXXXX); then
    ORC_SWITCHOVER_CLIENT_RC=1
    ORC_SWITCHOVER_CLIENT_OUTPUT="failed to create orchestrator client temp directory"
    return 1
  fi
  ORC_SWITCHOVER_CLIENT_OUTPUT_FILE="${ORC_SWITCHOVER_CLIENT_TEMP_DIR}/output"
  ORC_SWITCHOVER_CLIENT_RC_FILE="${ORC_SWITCHOVER_CLIENT_TEMP_DIR}/rc"
  ORC_SWITCHOVER_CLIENT_RC=""
  ORC_SWITCHOVER_CLIENT_OUTPUT=""
  (
    run_orchestrator_client_with_budget "${budget}" "$@" > "${ORC_SWITCHOVER_CLIENT_OUTPUT_FILE}" 2>&1
    printf '%s\n' "$?" > "${ORC_SWITCHOVER_CLIENT_RC_FILE}"
  ) &
  ORC_SWITCHOVER_CLIENT_PID=$!
  return 0
}

finish_orchestrator_client_background() {
  local wrapper_rc=0
  if [ -n "${ORC_SWITCHOVER_CLIENT_PID}" ]; then
    wait "${ORC_SWITCHOVER_CLIENT_PID}"
    wrapper_rc=$?
  fi

  ORC_SWITCHOVER_CLIENT_OUTPUT=$(cat "${ORC_SWITCHOVER_CLIENT_OUTPUT_FILE}" 2>/dev/null || true)
  if [ -s "${ORC_SWITCHOVER_CLIENT_RC_FILE}" ]; then
    ORC_SWITCHOVER_CLIENT_RC=$(cat "${ORC_SWITCHOVER_CLIENT_RC_FILE}")
  else
    ORC_SWITCHOVER_CLIENT_RC="${wrapper_rc}"
  fi
  rm -rf "${ORC_SWITCHOVER_CLIENT_TEMP_DIR}"
  ORC_SWITCHOVER_CLIENT_PID=""
  ORC_SWITCHOVER_CLIENT_OUTPUT_FILE=""
  ORC_SWITCHOVER_CLIENT_RC_FILE=""
  ORC_SWITCHOVER_CLIENT_TEMP_DIR=""
}

mysql_read_flags() {
  local host="$1"
  local budget="${MYSQL_ORC_SWITCHOVER_MYSQL_TIMEOUT_SECONDS:-1}"
  local connect_timeout="${MYSQL_ORC_SWITCHOVER_MYSQL_CONNECT_TIMEOUT_SECONDS:-1}"
  run_command_with_budget "${budget}" env MYSQL_PWD="${MYSQL_ROOT_PASSWORD}" mysql -u"${MYSQL_ROOT_USER}" -P3306 -h"${host}" \
    --connect-timeout="${connect_timeout}" --batch --skip-column-names \
    -e "SELECT @@global.read_only, @@global.super_read_only;" 2>&1
}

read_mysql_flags_pair() {
  local candidate="$1"
  local current="$2"
  local temp_dir candidate_output_file candidate_rc_file current_output_file current_rc_file
  local candidate_pid current_pid candidate_rc current_rc candidate_output current_output

  SWITCHOVER_VERIFY_CANDIDATE_RAW=""
  SWITCHOVER_VERIFY_CURRENT_RAW=""
  if ! temp_dir=$(mktemp -d /tmp/orc-switchover-readback.XXXXXX); then
    SWITCHOVER_VERIFY_CANDIDATE_FLAGS="<failed to create readback temp directory>"
    SWITCHOVER_VERIFY_CURRENT_FLAGS="<not checked>"
    return 1
  fi
  candidate_output_file="${temp_dir}/candidate-output"
  candidate_rc_file="${temp_dir}/candidate-rc"
  current_output_file="${temp_dir}/current-output"
  current_rc_file="${temp_dir}/current-rc"

  (
    mysql_read_flags "$candidate" > "${candidate_output_file}" 2>&1
    printf '%s\n' "$?" > "${candidate_rc_file}"
  ) &
  candidate_pid=$!

  (
    mysql_read_flags "$current" > "${current_output_file}" 2>&1
    printf '%s\n' "$?" > "${current_rc_file}"
  ) &
  current_pid=$!

  wait "${candidate_pid}" 2>/dev/null || true
  wait "${current_pid}" 2>/dev/null || true

  candidate_rc=$(cat "${candidate_rc_file}" 2>/dev/null || printf '1')
  current_rc=$(cat "${current_rc_file}" 2>/dev/null || printf '1')
  candidate_output=$(cat "${candidate_output_file}" 2>/dev/null || true)
  current_output=$(cat "${current_output_file}" 2>/dev/null || true)
  SWITCHOVER_VERIFY_CANDIDATE_RAW="${candidate_output}"
  SWITCHOVER_VERIFY_CURRENT_RAW="${current_output}"
  SWITCHOVER_VERIFY_CANDIDATE_FLAGS="rc=${candidate_rc} output=${candidate_output}"
  SWITCHOVER_VERIFY_CURRENT_FLAGS="rc=${current_rc} output=${current_output}"

  rm -rf "${temp_dir}"
  [ "$candidate_rc" = "0" ] && [ "$current_rc" = "0" ]
}

is_false_flag() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    0|off|false) return 0 ;;
    *) return 1 ;;
  esac
}

is_true_flag() {
  case "$(printf '%s' "$1" | tr '[:upper:]' '[:lower:]')" in
    1|on|true) return 0 ;;
    *) return 1 ;;
  esac
}

extract_mysql_read_flags() {
  local flags="$1"
  printf '%s\n' "$flags" | awk '
    NF >= 2 {
      read_only = tolower($1)
      super_read_only = tolower($2)
      if ((read_only == "0" || read_only == "1" || read_only == "on" || read_only == "off" || read_only == "true" || read_only == "false") &&
          (super_read_only == "0" || super_read_only == "1" || super_read_only == "on" || super_read_only == "off" || super_read_only == "true" || super_read_only == "false")) {
        last_read_only = $1
        last_super_read_only = $2
        found = 1
      }
    }
    END {
      if (!found) {
        exit 1
      }
      print last_read_only, last_super_read_only
    }
  '
}

is_writable_mysql() {
  local flags="$1"
  local parsed read_only super_read_only
  parsed=$(extract_mysql_read_flags "$flags") || return 1
  read -r read_only super_read_only <<< "$parsed"
  is_false_flag "$read_only" && is_false_flag "$super_read_only"
}

is_readonly_mysql() {
  local flags="$1"
  local parsed read_only super_read_only
  parsed=$(extract_mysql_read_flags "$flags") || return 1
  read -r read_only super_read_only <<< "$parsed"
  is_true_flag "$read_only" && is_true_flag "$super_read_only"
}

append_switchover_verify_history() {
  local attempt="$1"
  local entry
  entry=$(printf 'attempt %s: observed-candidate=%s; candidate-flags=%s; current-flags=%s' \
    "$attempt" "${SWITCHOVER_VERIFY_CANDIDATE:-<unset>}" \
    "${SWITCHOVER_VERIFY_CANDIDATE_FLAGS:-<unset>}" \
    "${SWITCHOVER_VERIFY_CURRENT_FLAGS:-<unset>}")
  if [ -z "${SWITCHOVER_VERIFY_HISTORY:-}" ]; then
    SWITCHOVER_VERIFY_HISTORY="$entry"
  else
    SWITCHOVER_VERIFY_HISTORY=$(printf '%s\n%s' "$SWITCHOVER_VERIFY_HISTORY" "$entry")
  fi
}

verify_switchover_closed_once() {
  local candidate="${KB_SWITCHOVER_CANDIDATE_NAME:-}"
  local master_from_orc precheck_budget rc
  precheck_budget="${MYSQL_ORC_SWITCHOVER_PRECHECK_TIMEOUT_SECONDS:-3}"

  if [ -z "$candidate" ]; then
    master_from_orc=$(run_orchestrator_client_with_budget "${precheck_budget}" -c which-cluster-master -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
    rc=$?
    if [ $rc -ne 0 ]; then
      SWITCHOVER_VERIFY_CANDIDATE_FLAGS="candidate lookup rc=${rc} output=${master_from_orc}"
      SWITCHOVER_VERIFY_CURRENT_FLAGS="<not checked>"
      return 1
    fi
    candidate="${master_from_orc%%:*}"
  fi
  SWITCHOVER_VERIFY_CANDIDATE="${candidate:-<empty>}"

  if [ -z "$candidate" ] || [ "$candidate" = "$KB_SWITCHOVER_CURRENT_NAME" ]; then
    SWITCHOVER_VERIFY_CANDIDATE_FLAGS="<candidate unresolved or still current>"
    SWITCHOVER_VERIFY_CURRENT_FLAGS="<not checked>"
    return 1
  fi

  if ! read_mysql_flags_pair "$candidate" "$KB_SWITCHOVER_CURRENT_NAME"; then
    return 1
  fi

  is_writable_mysql "$SWITCHOVER_VERIFY_CANDIDATE_RAW" && is_readonly_mysql "$SWITCHOVER_VERIFY_CURRENT_RAW"
}

switchover_verify_context() {
  local attempts="${MYSQL_ORC_SWITCHOVER_VERIFY_ATTEMPTS:-20}"
  local interval="${MYSQL_ORC_SWITCHOVER_VERIFY_INTERVAL_SECONDS:-1}"
  local window="${MYSQL_ORC_SWITCHOVER_VERIFY_WINDOW_SECONDS:-${MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS:-40}}"
  local ctx
  ctx=$(printf '  verify-attempts: %s\n  verify-interval-seconds: %s\n  verify-window-seconds: %s\n  precheck-timeout-seconds: %s\n  client-timeout-seconds: %s\n  mysql-timeout-seconds: %s\n  mysql-connect-timeout-seconds: %s\n  observed-candidate: %s\n  candidate-flags: %s\n  current-flags: %s' \
    "$attempts" "$interval" "$window" "${MYSQL_ORC_SWITCHOVER_PRECHECK_TIMEOUT_SECONDS:-3}" \
    "${MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS:-40}" \
    "${MYSQL_ORC_SWITCHOVER_MYSQL_TIMEOUT_SECONDS:-1}" \
    "${MYSQL_ORC_SWITCHOVER_MYSQL_CONNECT_TIMEOUT_SECONDS:-1}" \
    "${SWITCHOVER_VERIFY_CANDIDATE:-<unset>}" \
    "${SWITCHOVER_VERIFY_CANDIDATE_FLAGS:-<unset>}" "${SWITCHOVER_VERIFY_CURRENT_FLAGS:-<unset>}")
  printf '%s\n  verify-history:\n%s' "$ctx" "${SWITCHOVER_VERIFY_HISTORY:-<empty>}"
}

diagnose_switchover_not_converged() {
  local extra="${1:-}"
  local ctx
  ctx=$(switchover_verify_context)
  if [ -n "$extra" ]; then
    ctx=$(printf '%s\n%s' "$ctx" "$extra")
  fi
  switchover_diagnose_not_ready "post-switchover-not-converged" "$ctx" "yes"
}

verify_switchover_closed_window() {
  local attempts="${MYSQL_ORC_SWITCHOVER_VERIFY_ATTEMPTS:-20}"
  local interval="${MYSQL_ORC_SWITCHOVER_VERIFY_INTERVAL_SECONDS:-1}"
  local window="${MYSQL_ORC_SWITCHOVER_VERIFY_WINDOW_SECONDS:-${MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS:-40}}"
  local started="$SECONDS"
  local i

  SWITCHOVER_VERIFY_HISTORY=""
  i=1
  while [ "$i" -le "$attempts" ]; do
    if [ "$i" -gt 1 ] && [ $((SECONDS - started)) -ge "$window" ]; then
      break
    fi
    if verify_switchover_closed_once; then
      mysql_note "Switchover verified: candidate is writable and previous primary is read-only."
      return 0
    fi
    append_switchover_verify_history "$i"
    if [ "$i" -lt "$attempts" ] && [ $((SECONDS - started)) -lt "$window" ]; then
      sleep "$interval"
    fi
    i=$((i + 1))
  done

  return 1
}

verify_switchover_closed_or_defer() {
  if verify_switchover_closed_window; then
    return 0
  fi
  diagnose_switchover_not_converged
  return 1
}

orchestrator_client_context() {
  printf '  orchestrator-client-rc: %s\n  orchestrator-client-output:\n%s' \
    "${ORC_SWITCHOVER_CLIENT_RC:-<unset>}" "${ORC_SWITCHOVER_CLIENT_OUTPUT:-<empty>}"
}

run_switchover_client_and_verify() {
  local client_budget="$1"
  local verify_rc
  shift

  if ! start_orchestrator_client_background "${client_budget}" "$@"; then
    switchover_diagnose_not_ready "orchestrator-client-start-failed" \
      "$(orchestrator_client_context)" "yes"
    return 1
  fi
  if verify_switchover_closed_window; then
    verify_rc=0
  else
    verify_rc=1
  fi
  finish_orchestrator_client_background

  if [ "$verify_rc" -eq 0 ]; then
    if [ "${ORC_SWITCHOVER_CLIENT_RC:-0}" != "0" ]; then
      mysql_note "Switchover command returned non-zero (${ORC_SWITCHOVER_CLIENT_RC}) but post-check observed the target topology."
      if [ -n "${ORC_SWITCHOVER_CLIENT_OUTPUT:-}" ]; then
        mysql_note "${ORC_SWITCHOVER_CLIENT_OUTPUT}"
      fi
    fi
    return 0
  fi

  diagnose_switchover_not_converged "$(orchestrator_client_context)"
  if [ "${ORC_SWITCHOVER_CLIENT_RC:-0}" != "0" ]; then
    switchover_diagnose_not_ready "orchestrator-command-failed" \
      "$(printf '  rc: %s\n  observed:\n%s' "${ORC_SWITCHOVER_CLIENT_RC}" "${ORC_SWITCHOVER_CLIENT_OUTPUT:-<empty>}")" "yes"
  fi
  return 1
}

# This is magic for shellspec ut framework.
# When included from shellspec, __SOURCED__ is set and only functions are loaded.
${__SOURCED__:+false} : || return 0

# Check pod role
if [[ "$KB_SWITCHOVER_ROLE" != "primary" ]]; then
  mysql_note "Switchover not triggered for non-primary role, skipping."
  exit 0
fi

# Skip if KB_SWITCHOVER_CURRENT_NAME is not the master.
# Keep Orchestrator probing bounded; rc!=0 is a hard precheck failure and must
# not be mistaken for a master name (that previously made this guard exit 0).
precheck_budget="${MYSQL_ORC_SWITCHOVER_PRECHECK_TIMEOUT_SECONDS:-3}"

master_from_orc=$(run_orchestrator_client_with_budget "${precheck_budget}" -c which-cluster-master -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
rc=$?
if [ $rc -ne 0 ] || [ -z "$master_from_orc" ]; then
  mysql_error "Could not determine current master from Orchestrator (rc=${rc}): ${master_from_orc}"
fi

if [ "${KB_SWITCHOVER_CURRENT_NAME}" != "${master_from_orc%%:*}" ]; then
  mysql_note "Current instance is not the master, skipping."
  exit 0
fi

# Skip switch if there is only one instance
instances=$(run_orchestrator_client_with_budget "${precheck_budget}" -c which-cluster-instances -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
rc=$?
if [ $rc -ne 0 ]; then
  mysql_error "Could not list cluster instances from Orchestrator (rc=${rc}): ${instances}"
fi
instance_count=$(printf '%s\n' "$instances" | sed '/^$/d' | wc -l)
if [ "$instance_count" -le 1 ]; then
  mysql_note "Only one instance in cluster, cannot switchover."
  exit 0
fi

if [ -n "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
  # Switchover to specific candidate
  mysql_note "Initiating graceful switchover to: ${KB_SWITCHOVER_CANDIDATE_NAME}"
  if run_switchover_client_and_verify "${MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS:-40}" -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" \
    -d "${KB_SWITCHOVER_CANDIDATE_NAME}"; then
    exit 0
  fi
else
  # Auto-select candidate
  mysql_note "Initiating graceful switchover with auto-selected candidate"
  if run_switchover_client_and_verify "${MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS:-40}" -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}"; then
    exit 0
  fi
fi

exit 1
