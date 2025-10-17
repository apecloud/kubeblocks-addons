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

# Check pod role
if [[ "$KB_SWITCHOVER_ROLE" != "primary" ]]; then
  mysql_note "Switchover not triggered for non-primary role, skipping."
  exit 0
fi

# Skip if KB_SWITCHOVER_CURRENT_NAME is not the master
master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
if [ -z "$master_from_orc" ]; then
  mysql_error "Could not determine current master from Orchestrator"
fi

if [ "${KB_SWITCHOVER_CURRENT_NAME}" != "${master_from_orc%%:*}" ]; then
  mysql_note "Current instance is not the master, skipping."
  exit 0
fi

# Skip switch if there is only one instance
instance_count=$(/kubeblocks/orchestrator-client -c which-cluster-instances -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1 | wc -l)
if [ "$instance_count" -eq 1 ]; then
  mysql_note "Only one instance in cluster, cannot switchover."
  exit 0
fi

if [ -n "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
  # Switchover to specific candidate
  mysql_note "Initiating graceful switchover to: ${KB_SWITCHOVER_CANDIDATE_NAME}"
  result=$(/kubeblocks/orchestrator-client -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" \
    -d "${KB_SWITCHOVER_CANDIDATE_NAME}" 2>&1)
  exit_code=$?
else
  # Auto-select candidate
  mysql_note "Initiating graceful switchover with auto-selected candidate"
  result=$(/kubeblocks/orchestrator-client -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
  exit_code=$?
fi

if [ $exit_code -ne 0 ]; then
  mysql_error "Switchover command failed with exit code: ${result}"
fi