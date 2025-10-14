#! /bin/bash

set +e

master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i "${CLUSTER_NAME}")

if [ "${KB_AGENT_POD_NAME%%:*}" != "${master_from_orc%%:*}" ]; then
  echo "switchover not triggered for non-primary pod, nothing to do, exit 0."
  exit 0
fi

# skip switch if there is only one instance
if [ "$(/kubeblocks/orchestrator-client -c topology -i "${CLUSTER_NAME}" | wc -l)" -eq 1 ]; then
  echo "Only one instance, nothing to do, exit 0."
  exit 0
fi

# Execute switchover using orchestrator-client
if [ -n "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
  # Switchover to specific candidate
  echo "Initiating switchover to ${KB_SWITCHOVER_CANDIDATE_NAME}"
  result=$(/kubeblocks/orchestrator-client -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" \
    -d "${KB_SWITCHOVER_CANDIDATE_NAME}" 2>&1)
  exit_code=$?
else
  # Auto-select candidate
  echo "Initiating switchover with auto-selected candidate"
  result=$(/kubeblocks/orchestrator-client -c graceful-master-takeover-auto \
    -i "${KB_SWITCHOVER_CURRENT_NAME}" 2>&1)
  exit_code=$?
fi

# Check if command succeeded
if [ $exit_code -ne 0 ]; then
  echo "ERROR: Switchover command failed"
  echo "Output: ${result}"
  exit 1
fi

echo "SUCCESS: Switchover completed"
echo "Result: ${result}"
exit 0