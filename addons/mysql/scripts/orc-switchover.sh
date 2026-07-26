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

ORCHESTRATOR_CLIENT="${ORCHESTRATOR_CLIENT:-/kubeblocks/orchestrator-client}"

# Check pod role
if [[ "$KB_SWITCHOVER_ROLE" != "primary" ]]; then
  mysql_note "Switchover not triggered for non-primary role, skipping."
  exit 0
fi

# Keep stderr out of the command substitution. Otherwise an Orchestrator
# outage can be mistaken for a master name and silently skip the switchover.
master_from_orc=$("$ORCHESTRATOR_CLIENT" -c which-cluster-master -i "${KB_SWITCHOVER_CURRENT_NAME}")
rc=$?
if [ $rc -ne 0 ] || [ -z "$master_from_orc" ]; then
  mysql_error "Could not determine current master from Orchestrator (rc=${rc})"
fi

if [ "${KB_SWITCHOVER_CURRENT_NAME}" != "${master_from_orc%%:*}" ]; then
  mysql_note "Current instance is not the master, skipping."
  exit 0
fi

# Skip switch if there is only one instance.
instances=$("$ORCHESTRATOR_CLIENT" -c which-cluster-instances -i "${KB_SWITCHOVER_CURRENT_NAME}")
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
  result=$("$ORCHESTRATOR_CLIENT" -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" \
    -d "${KB_SWITCHOVER_CANDIDATE_NAME}" 2>&1)
  exit_code=$?
else
  # Auto-select candidate
  mysql_note "Initiating graceful switchover with auto-selected candidate"
  result=$("$ORCHESTRATOR_CLIENT" -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
  exit_code=$?
fi

if [ $exit_code -ne 0 ]; then
  mysql_error "Switchover command failed with exit code ${exit_code}: ${result}"
fi
