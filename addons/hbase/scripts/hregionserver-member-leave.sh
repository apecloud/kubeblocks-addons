#!/usr/bin/env bash
set -euo pipefail

: "${HBASE_HOME:=/opt/hbase}"

REGIONSERVER_HOST="${KB_LEAVE_MEMBER_POD_FQDN:-${KB_LEAVE_MEMBER_POD_NAME:-}}"
if [[ -z "${REGIONSERVER_HOST}" ]]; then
  echo "KB_LEAVE_MEMBER_POD_FQDN or KB_LEAVE_MEMBER_POD_NAME is required" >&2
  exit 1
fi

BALANCER_RESTORE_REQUIRED=false

# Runs an HBase shell command and prints its output.
# Parameters:
#   $1: HBase shell command.
# Returns:
#   0 when the shell command succeeds; non-zero otherwise.
hbase_shell() {
  printf '%s\n' "$1" | "${HBASE_HOME}/bin/hbase" shell -n 2>/dev/null
}

# Reads the current HBase balancer state.
# Parameters: none.
# Returns:
#   0 and prints true/false when the state is parsed successfully; non-zero otherwise.
get_balancer_state() {
  local output
  output="$(hbase_shell "balancer_enabled")" || return 1
  output="${output//$'\r'/}"
  if grep -Eq '(^|[[:space:]])true($|[[:space:]])' <<< "${output}"; then
    printf 'true\n'
    return 0
  fi
  if grep -Eq '(^|[[:space:]])false($|[[:space:]])' <<< "${output}"; then
    printf 'false\n'
    return 0
  fi
  return 1
}

# Restores the HBase balancer to its original state before exit.
# Parameters: none.
# Returns:
#   0 when no restoration is needed or restoration succeeds; non-zero otherwise.
restore_balancer() {
  if [[ "${BALANCER_RESTORE_REQUIRED}" == "true" ]]; then
    echo "Re-enabling balancer after RegionServer unload..."
    hbase_shell "balance_switch true" || {
      echo "Failed to re-enable the balancer" >&2
      return 1
    }
  fi
}

# Finalizes the script exit code after attempting balancer restoration.
# Parameters:
#   $1: The current script exit code before cleanup.
# Returns:
#   Does not return; exits with the final status code.
on_exit() {
  local rc="$1"
  restore_balancer || rc=1
  exit "${rc}"
}

trap 'on_exit $?' EXIT

ORIGINAL_BALANCER_STATE="$(get_balancer_state)" || {
  echo "Failed to determine the balancer state before unloading ${REGIONSERVER_HOST}" >&2
  exit 1
}

if [[ "${ORIGINAL_BALANCER_STATE}" == "true" ]]; then
  echo "Disabling balancer before unloading ${REGIONSERVER_HOST}..."
  hbase_shell "balance_switch false"
  BALANCER_RESTORE_REQUIRED=true
else
  echo "Balancer is already disabled before unloading ${REGIONSERVER_HOST}."
fi

echo "Unloading regions from ${REGIONSERVER_HOST}..."
"${HBASE_HOME}/bin/hbase" org.apache.hadoop.hbase.util.RegionMover -m 6 -r "${REGIONSERVER_HOST}" -o unload
echo "RegionServer ${REGIONSERVER_HOST} unloaded"
