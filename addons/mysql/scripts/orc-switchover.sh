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

run_orchestrator_client_with_budget() {
  local budget="${MYSQL_ORC_SWITCHOVER_CLIENT_TIMEOUT_SECONDS:-35}"

  if command -v timeout >/dev/null 2>&1; then
    timeout "${budget}s" /kubeblocks/orchestrator-client "$@"
    return $?
  fi

  local output_file pid timer_pid rc
  output_file="/tmp/orc-switchover-${$}-${RANDOM}.out"
  /kubeblocks/orchestrator-client "$@" > "${output_file}" 2>&1 &
  pid=$!
  (
    sleep "${budget}"
    kill "${pid}" 2>/dev/null || true
    sleep 1
    kill -9 "${pid}" 2>/dev/null || true
  ) &
  timer_pid=$!

  wait "${pid}"
  rc=$?
  kill "${timer_pid}" 2>/dev/null || true
  wait "${timer_pid}" 2>/dev/null || true
  cat "${output_file}"
  rm -f "${output_file}"
  return $rc
}

mysql_read_flags() {
  local host="$1"
  mysql -u"${MYSQL_ROOT_USER}" -p"${MYSQL_ROOT_PASSWORD}" -P3306 -h"${host}" \
    --connect-timeout=2 --batch --skip-column-names \
    -e "SELECT @@global.read_only, @@global.super_read_only;" 2>&1
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

is_writable_mysql() {
  local flags="$1"
  local read_only super_read_only
  read_only=$(printf '%s\n' "$flags" | awk 'NR==1 {print $1}')
  super_read_only=$(printf '%s\n' "$flags" | awk 'NR==1 {print $2}')
  is_false_flag "$read_only" && is_false_flag "$super_read_only"
}

is_readonly_mysql() {
  local flags="$1"
  local read_only super_read_only
  read_only=$(printf '%s\n' "$flags" | awk 'NR==1 {print $1}')
  super_read_only=$(printf '%s\n' "$flags" | awk 'NR==1 {print $2}')
  is_true_flag "$read_only" && is_true_flag "$super_read_only"
}

verify_switchover_closed_once() {
  local candidate="${KB_SWITCHOVER_CANDIDATE_NAME:-}"
  local master_from_orc candidate_flags current_flags rc

  if [ -z "$candidate" ]; then
    master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>/dev/null || true)
    candidate="${master_from_orc%%:*}"
  fi
  SWITCHOVER_VERIFY_CANDIDATE="${candidate:-<empty>}"

  if [ -z "$candidate" ] || [ "$candidate" = "$KB_SWITCHOVER_CURRENT_NAME" ]; then
    SWITCHOVER_VERIFY_CANDIDATE_FLAGS="<candidate unresolved or still current>"
    SWITCHOVER_VERIFY_CURRENT_FLAGS="<not checked>"
    return 1
  fi

  candidate_flags=$(mysql_read_flags "$candidate")
  rc=$?
  SWITCHOVER_VERIFY_CANDIDATE_FLAGS="rc=${rc} output=${candidate_flags}"
  if [ $rc -ne 0 ]; then
    SWITCHOVER_VERIFY_CURRENT_FLAGS="<not checked>"
    return 1
  fi

  current_flags=$(mysql_read_flags "$KB_SWITCHOVER_CURRENT_NAME")
  rc=$?
  SWITCHOVER_VERIFY_CURRENT_FLAGS="rc=${rc} output=${current_flags}"
  if [ $rc -ne 0 ]; then
    return 1
  fi

  is_writable_mysql "$candidate_flags" && is_readonly_mysql "$current_flags"
}

verify_switchover_closed_or_defer() {
  local attempts="${MYSQL_ORC_SWITCHOVER_VERIFY_ATTEMPTS:-6}"
  local interval="${MYSQL_ORC_SWITCHOVER_VERIFY_INTERVAL_SECONDS:-2}"
  local i ctx

  i=1
  while [ "$i" -le "$attempts" ]; do
    if verify_switchover_closed_once; then
      mysql_note "Switchover verified: candidate is writable and previous primary is read-only."
      return 0
    fi
    sleep "$interval"
    i=$((i + 1))
  done

  ctx=$(printf '  verify-attempts: %s\n  verify-interval-seconds: %s\n  observed-candidate: %s\n  candidate-flags: %s\n  current-flags: %s' \
    "$attempts" "$interval" "${SWITCHOVER_VERIFY_CANDIDATE:-<unset>}" \
    "${SWITCHOVER_VERIFY_CANDIDATE_FLAGS:-<unset>}" "${SWITCHOVER_VERIFY_CURRENT_FLAGS:-<unset>}")
  switchover_diagnose_not_ready "post-switchover-not-converged" "$ctx" "yes"
  return 1
}

# Check pod role
if [[ "$KB_SWITCHOVER_ROLE" != "primary" ]]; then
  mysql_note "Switchover not triggered for non-primary role, skipping."
  exit 0
fi

# Skip if KB_SWITCHOVER_CURRENT_NAME is not the master.
# Keep stderr out of the command substitution: on an Orchestrator outage the
# client's error text must not be mistaken for a master name (it previously
# made this guard exit 0 and the switchover was silently skipped as success).
master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i "${KB_SWITCHOVER_CURRENT_NAME}")
rc=$?
if [ $rc -ne 0 ] || [ -z "$master_from_orc" ]; then
  mysql_error "Could not determine current master from Orchestrator (rc=${rc})"
fi

if [ "${KB_SWITCHOVER_CURRENT_NAME}" != "${master_from_orc%%:*}" ]; then
  mysql_note "Current instance is not the master, skipping."
  exit 0
fi

# Skip switch if there is only one instance
instances=$(/kubeblocks/orchestrator-client -c which-cluster-instances -i "${KB_SWITCHOVER_CURRENT_NAME}")
rc=$?
if [ $rc -ne 0 ]; then
  mysql_error "Could not list cluster instances from Orchestrator (rc=${rc})"
fi
instance_count=$(printf '%s\n' "$instances" | sed '/^$/d' | wc -l)
if [ "$instance_count" -le 1 ]; then
  mysql_note "Only one instance in cluster, cannot switchover."
  exit 0
fi

if [ -n "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
  # Switchover to specific candidate
  mysql_note "Initiating graceful switchover to: ${KB_SWITCHOVER_CANDIDATE_NAME}"
  result=$(run_orchestrator_client_with_budget -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" \
    -d "${KB_SWITCHOVER_CANDIDATE_NAME}" 2>&1)
  exit_code=$?
else
  # Auto-select candidate
  mysql_note "Initiating graceful switchover with auto-selected candidate"
  result=$(run_orchestrator_client_with_budget -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
  exit_code=$?
fi

if [ $exit_code -ne 0 ]; then
  if verify_switchover_closed_or_defer; then
    mysql_note "Switchover command returned non-zero (${exit_code}) but post-check observed the target topology."
    exit 0
  fi
  switchover_diagnose_not_ready "orchestrator-command-failed" \
    "$(printf '  rc: %s\n  observed:\n%s' "$exit_code" "$result")" "yes"
  exit 1
fi

verify_switchover_closed_or_defer
