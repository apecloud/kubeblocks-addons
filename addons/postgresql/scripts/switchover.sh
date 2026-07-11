#!/bin/bash

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/kb-scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

# Bounded-wait budget (kbagent clamps every action call at 60s):
#   leader query  : curl -m 5
#   switchover API: curl -m 20 (patroni blocks until the switchover attempt finishes)
#   verification  : candidate path only, up to 4 attempts x (curl -m 3 + sleep 2) ~= 20s
# worst case ~= 45s (candidate) / ~25s (no candidate), under cmpd timeoutSeconds 50.
SWITCHOVER_VERIFY_ATTEMPTS=${SWITCHOVER_VERIFY_ATTEMPTS:-4}
SWITCHOVER_VERIFY_INTERVAL=${SWITCHOVER_VERIFY_INTERVAL:-2}

switchover_diagnose_not_ready() {
  local phase=$1
  local ctx=$2
  local retry_safe=$3
  {
    echo "switchover diagnosis:"
    echo "  action: switchover"
    echo "  phase: ${phase}"
    echo "${ctx}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

# Prints the name of the current leader as seen by patroni. Matches both
# "leader" and "standby_leader" so switchover works in standby clusters too.
# Optional $1 overrides the curl timeout: the verification loop passes 3s so
# the bounded-wait budget stays under the action timeout (see comment above).
get_current_leader() {
  local timeout=${1:-5}
  curl -s -m "${timeout}" http://localhost:8008/cluster 2>/dev/null \
    | jq -r '[.members[] | select(.role == "leader" or .role == "standby_leader") | .name] | first // empty' 2>/dev/null
}

# Sends the switchover request to patroni and fails on connection errors or
# non-2xx responses instead of swallowing them.
request_switchover() {
  local leader=$1
  local candidate=$2
  local payload response http_code body

  if [ -n "${candidate}" ]; then
    payload="{\"leader\":\"${leader}\",\"candidate\":\"${candidate}\"}"
  else
    payload="{\"leader\":\"${leader}\"}"
  fi

  if ! response=$(curl -s -m 20 -w "\n%{http_code}" -XPOST -d "${payload}" "http://127.0.0.1:8008/switchover"); then
    switchover_diagnose_not_ready "switchover-api-unreachable" "  leader: ${leader}" "yes"
    return 1
  fi
  http_code=$(printf '%s\n' "${response}" | tail -n 1)
  body=$(printf '%s\n' "${response}" | sed '$d')
  echo "Switchover API response (HTTP ${http_code}): ${body}"
  case "${http_code}" in
    2*)
      return 0
      ;;
    5*)
      # e.g. patroni 503 "switchover is not possible" while replicas catch up
      switchover_diagnose_not_ready "switchover-rejected" "  http_code: ${http_code}
  response: ${body}" "yes"
      return 1
      ;;
    *)
      switchover_diagnose_not_ready "switchover-rejected" "  http_code: ${http_code}
  response: ${body}" "no"
      return 1
      ;;
  esac
}

# Positively confirms a candidate switchover: leadership must have left the
# old leader and landed on the requested candidate. The no-candidate path does
# not use this — patroni's POST /switchover is synchronous, so the checked
# 2xx response already confirms the switchover completed (reviewer direction
# in PR #3035: do not poll-verify the no-candidate path).
verify_switchover() {
  local old_leader=$1
  local candidate=$2
  local attempt new_leader

  for attempt in $(seq 1 "${SWITCHOVER_VERIFY_ATTEMPTS}"); do
    new_leader=$(get_current_leader 3)
    if [ -n "${new_leader}" ] && [ "${new_leader}" != "${old_leader}" ]; then
      if [ -n "${candidate}" ] && [ "${new_leader}" != "${candidate}" ]; then
        switchover_diagnose_not_ready "switchover-wrong-leader" "  expected_leader: ${candidate}
  observed_leader: ${new_leader}" "no"
        return 1
      fi
      echo "Switchover verified: new leader is ${new_leader}"
      return 0
    fi
    echo "Switchover not confirmed yet (attempt ${attempt}/${SWITCHOVER_VERIFY_ATTEMPTS}, observed leader: ${new_leader:-<none>})"
    sleep "${SWITCHOVER_VERIFY_INTERVAL}"
  done

  switchover_diagnose_not_ready "switchover-not-confirmed" "  old_leader: ${old_leader}
  observed_leader: ${new_leader:-<none>}
  attempts: ${SWITCHOVER_VERIFY_ATTEMPTS}" "yes"
  return 1
}

switchover() {
  # CURRENT_POD_NAME defined in the switchover action env
  if is_empty "$CURRENT_POD_NAME" ; then
    echo "CURRENT_POD_NAME is not set. Exiting..."
    exit 1
  fi

  POSTGRES_PRIMARY_POD_NAME=$(get_current_leader)
  if is_empty "$POSTGRES_PRIMARY_POD_NAME"; then
    switchover_diagnose_not_ready "leader-not-resolved" "  detail: cannot determine current leader from patroni /cluster" "yes"
    exit 1
  fi

  if [[ $POSTGRES_PRIMARY_POD_NAME != "$CURRENT_POD_NAME" ]]; then
    # KubeBlocks invoked the action on the pod it believes is primary, but
    # patroni disagrees. Only report success when the desired end state is
    # already positively observed.
    if ! is_empty "$KB_SWITCHOVER_CANDIDATE_NAME"; then
      if [[ $POSTGRES_PRIMARY_POD_NAME == "$KB_SWITCHOVER_CANDIDATE_NAME" ]]; then
        echo "Switchover already completed: current leader is the candidate ${KB_SWITCHOVER_CANDIDATE_NAME}. Exiting."
        exit 0
      fi
      switchover_diagnose_not_ready "leader-mismatch" "  current_pod: ${CURRENT_POD_NAME}
  observed_leader: ${POSTGRES_PRIMARY_POD_NAME}
  candidate: ${KB_SWITCHOVER_CANDIDATE_NAME}" "no"
      exit 1
    fi
    echo "Leadership already moved to ${POSTGRES_PRIMARY_POD_NAME}; nothing to do for ${CURRENT_POD_NAME}. Exiting."
    exit 0
  fi

  # KB_SWITCHOVER_CANDIDATE_NAME is built-in env in the switchover action injected by the KubeBlocks controller
  if ! is_empty "$KB_SWITCHOVER_CANDIDATE_NAME"; then
    echo "Current pod: ${CURRENT_POD_NAME} performs switchover. Leader: ${POSTGRES_PRIMARY_POD_NAME}, Candidate: ${KB_SWITCHOVER_CANDIDATE_NAME}"
    request_switchover "$POSTGRES_PRIMARY_POD_NAME" "$KB_SWITCHOVER_CANDIDATE_NAME" || exit 1
    verify_switchover "$POSTGRES_PRIMARY_POD_NAME" "$KB_SWITCHOVER_CANDIDATE_NAME" || exit 1
  else
    echo "Current pod: ${CURRENT_POD_NAME} performs switchover without candidate. Leader: ${POSTGRES_PRIMARY_POD_NAME}"
    # No post-hoc verification here: patroni's /switchover is synchronous and
    # request_switchover already fails on any non-2xx result. Role convergence
    # is then proven by the roleProbe (05c). Reviewer direction in PR #3035.
    request_switchover "$POSTGRES_PRIMARY_POD_NAME" "" || exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
  echo "switchover not triggered for primary, nothing to do, exit 0."
  exit 0
fi
# main
load_common_library
switchover
