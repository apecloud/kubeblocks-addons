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

# memberLeave contract: KubeBlocks injects the LEAVING member's identity as
# KB_LEAVE_MEMBER_POD_NAME; the action may execute on a different pod, so
# KB_AGENT_POD_NAME (the execution pod) is only a fallback for older runtimes.
leave_member="${KB_LEAVE_MEMBER_POD_NAME:-${KB_AGENT_POD_NAME}}"
if [ -z "$leave_member" ]; then
  mysql_error "Neither KB_LEAVE_MEMBER_POD_NAME nor KB_AGENT_POD_NAME is set"
fi

# Forget instance from Orchestrator
if /kubeblocks/orchestrator-client -c forget -i "${leave_member}" 2>&1; then
  mysql_note "Forget command executed"
else
  mysql_note "Forget command failed, continuing anyway"
fi

sleep 3

# Verify instance was forgotten. "Instance not found" and "Orchestrator is
# down" both yield an empty query result, so prove Orchestrator is reachable
# first - otherwise an outage would be reported as a successful removal.
mysql_note "Verifying instance was forgotten..."
if ! /kubeblocks/orchestrator-client -c clusters >/dev/null 2>&1; then
  mysql_error "Orchestrator unreachable; cannot verify removal of ${leave_member}"
fi
instance_info=$(/kubeblocks/orchestrator-client -c instance -i "${leave_member}" 2>/dev/null || true)

if [ -z "$instance_info" ]; then
  mysql_note "Instance ${leave_member} successfully removed from Orchestrator"
  exit 0
fi
mysql_error "Instance ${leave_member} still exists in Orchestrator"