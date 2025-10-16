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

# Forget instance from Orchestrator
if /kubeblocks/orchestrator-client -c forget -i "${KB_AGENT_POD_NAME}" 2>&1; then
  mysql_note "Forget command executed"
else
  mysql_note "Forget command failed, continuing anyway"
fi

sleep 3

# Verify instance was forgotten
mysql_note "Verifying instance was forgotten..."
instance_info=$(/kubeblocks/orchestrator-client -c instance -i "${KB_AGENT_POD_NAME}" 2>/dev/null || echo "")

if [ -z "$instance_info" ]; then
  mysql_note "Instance ${KB_AGENT_POD_NAME} successfully removed from Orchestrator"
  exit 0
fi
mysql_error "Instance ${KB_AGENT_POD_NAME} still exists in Orchestrator"