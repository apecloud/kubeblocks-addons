#!/bin/bash
set +e

# Configuration
TIMEOUT=${timeout:-5}  # Default 5 seconds if not set
CHECK_INTERVAL=${check_interval:-1}  # Check every second

# Function to check if instance exists
check_instance_exists() {
  local instance_result=$(/kubeblocks/orchestrator-client -c instance -i ${self_service_name} 2>/dev/null || echo "")
  local alias_result=$(/kubeblocks/orchestrator-client -c which-cluster-alias -i ${self_service_name} 2>/dev/null || echo "")

  if [ -z "$instance_result" ] && [ -z "$alias_result" ]; then
    return 1  # Instance does not exist
  else
    return 0  # Instance still exists
  fi
}

# Main logic
master_from_orc=$(/kubeblocks/orchestrator-client -c which-cluster-master -i ${CLUSTER_NAME})

if [ -z "$master_from_orc" ]; then
  echo "ERROR: Could not determine current master from orchestrator"
  exit 1
fi

self_service_name=$(echo "${KB_LEAVE_MEMBER_POD_NAME}" | tr '_' '-' | tr '[:upper:]' '[:lower:]' )

echo "Current master: ${master_from_orc}"
echo "This instance: ${self_service_name}"

if [ "${self_service_name%%:*}" == "${master_from_orc%%:*}" ]; then
  echo "This instance IS the current master, initiating failover..."
  # Force master failover
  if ! /kubeblocks/orchestrator-client -c force-master-takeover -i ${CLUSTER_NAME}; then
    echo "ERROR: Failed to initiate master takeover"
    exit 1
  fi

  echo "Failover initiated, waiting for new master to be elected..."

  # Wait for master to change
  start_time=$(date +%s)
  elapsed=0
  new_master=""

  while true; do
    current_time=$(date +%s)
    elapsed=$((current_time - start_time))

    # Check timeout
    if [ $elapsed -gt $TIMEOUT ]; then
      echo "ERROR: Timeout after ${elapsed}s waiting for master switchover"
      echo "  Old master: ${master_from_orc}"
      echo "  Current master: ${new_master:-unknown}"
      exit 1
    fi

    # Check current master
    new_master=$(/kubeblocks/orchestrator-client -c which-cluster-master -i ${CLUSTER_NAME} 2>/dev/null)

    if [ -z "$new_master" ]; then
      echo "WARNING: Could not determine current master (${elapsed}s elapsed)"
    elif [ "${self_service_name%%:*}" != "${new_master%%:*}" ]; then
      # Master has changed to a different instance
      echo "SUCCESS: Switchover completed (${elapsed}s elapsed)"
      echo "  Old master: ${master_from_orc}"
      echo "  New master: ${new_master}"
      exit 0
    fi

    sleep $CHECK_INTERVAL
  done
fi

echo "Starting cleanup for instance: ${self_service_name}"

# Step 1: Reset and forget the instance
echo "Resetting replica..."
/kubeblocks/orchestrator-client -c reset-replica -i ${self_service_name} || true

echo "Forgetting instance..."
/kubeblocks/orchestrator-client -c forget -i ${self_service_name} || true

# Step 2: Wait for complete removal
echo "Waiting for instance to be completely removed..."
start_time=$(date +%s)
elapsed=0

while check_instance_exists; do
  current_time=$(date +%s)
  elapsed=$((current_time - start_time))

  # Check timeout
  if [ $elapsed -gt $TIMEOUT ]; then
    echo "ERROR: Timeout after ${elapsed}s waiting for instance ${self_service_name} to be removed"
    cluster_alias=$(/kubeblocks/orchestrator-client -c which-cluster-alias -i ${self_service_name} 2>/dev/null || echo "none")
    instance_info=$(/kubeblocks/orchestrator-client -c instance -i ${self_service_name} 2>/dev/null || echo "none")
    echo "  Cluster alias: $cluster_alias"
    echo "  Instance info: $instance_info"
    exit 1
  fi

  # Progress indicator every 10 seconds
  if [ $((elapsed % 10)) -eq 0 ] && [ $elapsed -gt 0 ]; then
    echo "Still waiting... (${elapsed}s elapsed)"
  fi

  sleep $CHECK_INTERVAL
done

# Success
echo "SUCCESS: Instance ${self_service_name} successfully removed (${elapsed}s elapsed)"
exit 0