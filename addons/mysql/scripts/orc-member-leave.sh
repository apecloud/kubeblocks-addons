#!/bin/bash

mysql_log() {
  local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
  printf '%s\n' "$text"
}
mysql_note() {
  mysql_log "$@"
}

member_leave_diagnose_not_ready() {
  local phase="$1"
  local ctx="$2"
  local retry_safe="$3"
  {
    echo "orc memberLeave diagnosis:"
    echo "  action: memberLeave"
    echo "  phase: ${phase}"
    echo "  leaving-member: ${KB_LEAVE_MEMBER_POD_NAME:-${KB_AGENT_POD_NAME:-<unset>}}"
    echo "${ctx}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

run_command_with_budget() {
  local budget="$1"
  shift
  if command -v timeout >/dev/null 2>&1; then
    timeout -k 1s "${budget}s" "$@"
    return $?
  fi

  local temp_dir output_file error_file timeout_file pid timer_pid rc
  temp_dir=$(mktemp -d /tmp/orc-member-leave.XXXXXX) || return 1
  output_file="${temp_dir}/output"
  error_file="${temp_dir}/error"
  timeout_file="${temp_dir}/timeout"
  "$@" > "${output_file}" 2> "${error_file}" &
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
  cat "${error_file}" >&2
  if [ -s "${timeout_file}" ]; then
    rc=124
  fi
  rm -rf "${temp_dir}"
  return "$rc"
}

run_orchestrator_client_with_budget() {
  local budget="$1"
  shift
  run_command_with_budget "${budget}" /kubeblocks/orchestrator-client "$@"
}

run_member_leave() {
  local leave_member budget settle_seconds output rc
  leave_member="${KB_LEAVE_MEMBER_POD_NAME:-${KB_AGENT_POD_NAME:-}}"
  budget="${MYSQL_ORC_MEMBER_LEAVE_CLIENT_TIMEOUT_SECONDS:-10}"
  settle_seconds="${MYSQL_ORC_MEMBER_LEAVE_SETTLE_SECONDS:-3}"
  if [ -z "$leave_member" ]; then
    member_leave_diagnose_not_ready "leaving-member-missing" \
      "  required-env: KB_LEAVE_MEMBER_POD_NAME or KB_AGENT_POD_NAME" "no"
    return 1
  fi

  output=$(run_orchestrator_client_with_budget "${budget}" -c forget -i "${leave_member}" 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    member_leave_diagnose_not_ready "forget-command-failed" \
      "$(printf '  rc: %s\n  output: %s' "$rc" "${output:-<empty>}")" "yes"
    return 1
  fi
  mysql_note "Forget command executed"

  sleep "${settle_seconds}"
  mysql_note "Verifying instance was forgotten..."
  output=$(run_orchestrator_client_with_budget "${budget}" -c clusters 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    member_leave_diagnose_not_ready "orchestrator-unreachable" \
      "$(printf '  rc: %s\n  output: %s' "$rc" "${output:-<empty>}")" "yes"
    return 1
  fi

  output=$(run_orchestrator_client_with_budget "${budget}" -c all-instances 2>&1)
  rc=$?
  if [ "$rc" -ne 0 ]; then
    member_leave_diagnose_not_ready "instance-verification-failed" \
      "$(printf '  rc: %s\n  output: %s' "$rc" "${output:-<empty>}")" "yes"
    return 1
  fi
  if ! printf '%s\n' "$output" | awk -F: -v target="$leave_member" '$1 == target { found = 1 } END { exit found ? 0 : 1 }'; then
    mysql_note "Instance ${leave_member} successfully removed from Orchestrator"
    return 0
  fi

  member_leave_diagnose_not_ready "instance-still-present" \
    "  observed: ${output}" "yes"
  return 1
}

# ShellSpec includes this file to test functions without executing the action.
${__SOURCED__:+false} : || return 0

run_member_leave
