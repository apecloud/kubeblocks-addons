#!/bin/sh
# https://www.elastic.co/guide/en/elasticsearch/reference/7.7/add-elasticsearch-nodes.html
# Enhanced with safe scale-down process following Elasticsearch best practices

set -eu

# Configuration
MAX_WAIT_TIME=${MAX_WAIT_TIME:-1800}  # 30 minutes max wait time
RETRY_COUNT=${RETRY_COUNT:-3}
RETRY_DELAY=${RETRY_DELAY:-5}
HEALTH_CHECK_INTERVAL=${HEALTH_CHECK_INTERVAL:-10}

# Setup basic auth if credentials are available
if [ -n "${ELASTIC_USER_PASSWORD:-}" ]; then
  BASIC_AUTH="-u elastic:${ELASTIC_USER_PASSWORD}"
else
  BASIC_AUTH=''
fi

# Check if we are using IPv6
if echo "${POD_IP:-}" | grep -q ':'; then
  LOOPBACK="[::1]"
else
  LOOPBACK=127.0.0.1
fi

if [ "${TLS_ENABLED:-false}" == "true" ]; then
  READINESS_PROBE_PROTOCOL=https
else
  READINESS_PROBE_PROTOCOL=http
fi

endpoint="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200"
common_options="-k --fail --max-time 30 --retry ${RETRY_COUNT} ${BASIC_AUTH}"

echo "Starting safe removal of node $KB_LEAVE_MEMBER_POD_NAME"

# Get Elasticsearch version
version=$(curl ${common_options} -s ${endpoint} | jq -r .version.number)
if [ $? != 0 ]; then
  echo "ERROR: Failed to get Elasticsearch version"
  exit 1
fi
major_version=${version%%.*}
echo "Detected Elasticsearch version: $version (major: $major_version)"

# Utility functions
log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

# Check cluster health status
check_cluster_health() {
  local status=$(curl ${common_options} -s "${endpoint}/_cluster/health" | jq -r '.status')
  if [ $? != 0 ]; then
    error_exit "Failed to get cluster health"
  fi
  echo "$status"
}

# Wait for cluster to reach desired status
wait_for_cluster_status() {
  local desired_status=$1
  local timeout=$2
  local start_time=$(date +%s)

  log "Waiting for cluster to reach $desired_status status..."
  while true; do
    local current_status=$(check_cluster_health)
    if [ "$current_status" = "$desired_status" ]; then
      log "Cluster reached $desired_status status"
      return 0
    fi

    local elapsed=$(( $(date +%s) - start_time ))
    if [ $elapsed -gt $timeout ]; then
      error_exit "Timeout waiting for cluster to reach $desired_status status (current: $current_status)"
    fi

    log "Current cluster status: $current_status, waiting..."
    sleep $HEALTH_CHECK_INTERVAL
  done
}

# Check if node has any shards
check_node_shards() {
  local node_name=$1
  local shard_count=$(curl ${common_options} -s "${endpoint}/_cat/shards?v" | grep "$node_name" | wc -l)
  echo "$shard_count"
}

# Set shard allocation exclusion for the node
set_shard_exclusion() {
  local node_name=$1

  log "Setting shard allocation exclusion for node: $node_name"
  local response=$(curl ${common_options} -s -X PUT "${endpoint}/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d "{\"persistent\": {\"cluster.routing.allocation.exclude._name\": \"${node_name}\"}}")

  if [ $? != 0 ]; then
    error_exit "Failed to set shard allocation exclusion"
  fi

  echo "$response" | jq -r '.acknowledged' | grep -q "true" || error_exit "Shard exclusion not acknowledged"
  log "Successfully set shard allocation exclusion"
}

# Clear shard allocation exclusion
clear_shard_exclusion() {
  local node_name=$1

  log "Clearing shard allocation exclusion for node: $node_name"
  # Clear all possible exclusion fields to ensure complete cleanup
  local response=$(curl ${common_options} -s -X PUT "${endpoint}/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d "{\"persistent\": {\"cluster.routing.allocation.exclude._name\": null, \"cluster.routing.allocation.exclude._ip\": null, \"cluster.routing.allocation.exclude._host\": null}}")

  if [ $? != 0 ]; then
    log "WARNING: Failed to clear shard allocation exclusion"
  else
    echo "$response" | jq -r '.acknowledged' | grep -q "true" || log "WARNING: Shard exclusion clearing not acknowledged"
    log "Successfully cleared shard allocation exclusion"
  fi
}

# Check if node is a master-eligible node
is_master_node() {
  local node_name=$1
  local is_master=$(curl ${common_options} -s "${endpoint}/_nodes/${node_name}" | jq -r '.nodes | to_entries[0].value.roles | contains(["master"])')
  if [ "$is_master" = "true" ]; then
    return 0
  else
    return 1
  fi
}

# Add node to voting config exclusions (ES 7.0+)
add_voting_exclusion() {
  local node_name=$1

  if [ "$major_version" -lt 7 ]; then
    log "Skipping voting config exclusion (not supported in ES $major_version.x)"
    return 0
  fi

  local url=""
  if [ "$major_version" -eq 7 ]; then
    # Extract minor version for comparison
    minor_version=$(echo "$version" | cut -d'.' -f2)
    if [ "$minor_version" -lt 8 ] 2>/dev/null; then
      url="${endpoint}/_cluster/voting_config_exclusions/${node_name}"
    else
      url="${endpoint}/_cluster/voting_config_exclusions?node_names=${node_name}"
    fi
  else
    url="${endpoint}/_cluster/voting_config_exclusions?node_names=${node_name}"
  fi

  log "Adding node $node_name to voting config exclusions"
  local response=$(curl ${common_options} -s -X POST "$url")

  if [ $? != 0 ]; then
    log "WARNING: Failed to add node to voting config exclusions, may be the list is full"
    # Try to clear exclusions first
    curl ${common_options} -X DELETE "${endpoint}/_cluster/voting_config_exclusions?pretty&wait_for_removal=false" || true
    response=$(curl ${common_options} -s -X POST "$url")
    if [ $? != 0 ]; then
      error_exit "Failed to add node to voting config exclusions after clearing"
    fi
  fi

  log "Successfully added node to voting config exclusions"
}

# Main safe scale-down process
safe_scale_down() {
  local node_name=$KB_LEAVE_MEMBER_POD_NAME
  local start_time=$(date +%s)

  log "=== Starting safe scale-down process for node: $node_name ==="

  # Step 1: Initial health check
  log "Step 1: Performing initial cluster health check"
  local initial_status=$(check_cluster_health)
  log "Initial cluster status: $initial_status"

  if [ "$initial_status" != "green" ] && [ "$initial_status" != "yellow" ]; then
    error_exit "Cluster is not in a healthy state (status: $initial_status). Please resolve cluster issues before scaling down."
  fi

  # Step 2: Check if node is master-eligible
  if is_master_node "$node_name"; then
    log "WARNING: Node $node_name is master-eligible. Adding to voting config exclusions."
    add_voting_exclusion "$node_name"
  fi

  # Step 3: Check current shards on the node
  local initial_shard_count=$(check_node_shards "$node_name")
  log "Node $node_name currently has $initial_shard_count shards"

  # Step 4: Set shard allocation exclusion
  log "Step 2: Setting shard allocation exclusion to migrate shards away from node"
  set_shard_exclusion "$node_name"

  # Step 5: Wait for shards to migrate
  log "Step 3: Waiting for shards to migrate from node $node_name"
  local migration_start=$(date +%s)

  while true; do
    local current_shard_count=$(check_node_shards "$node_name")
    local current_status=$(check_cluster_health)

    log "Current shard count on $node_name: $current_shard_count, cluster status: $current_status"

    # Check if migration is complete
    if [ "$current_shard_count" -eq 0 ]; then
      log "All shards have been migrated from node $node_name"
      break
    fi

    # Check for timeout
    local elapsed=$(( $(date +%s) - migration_start ))
    if [ $elapsed -gt $MAX_WAIT_TIME ]; then
      error_exit "Timeout waiting for shard migration to complete ($MAX_WAIT_TIME seconds)"
    fi

    # Check cluster health during migration
    if [ "$current_status" = "red" ]; then
      log "WARNING: Cluster became red during migration, but continuing..."
    fi

    sleep $HEALTH_CHECK_INTERVAL
  done

  # Step 6: Wait for cluster to return to healthy state
  log "Step 4: Ensuring cluster returns to healthy state"
  wait_for_cluster_status "green" 300

  # Step 7: Final verification
  log "Step 5: Performing final verification"
  local final_status=$(check_cluster_health)
  local final_shard_count=$(check_node_shards "$node_name")

  if [ "$final_shard_count" -gt 0 ]; then
    log "WARNING: Node still has $final_shard_count shards after migration"
  fi

  if [ "$final_status" != "green" ]; then
    log "WARNING: Cluster is not green after migration (status: $final_status)"
  fi

  # Step 8: Node can now be safely removed
  log "Node $node_name can now be safely removed from the cluster"
  log "=== Safe scale-down process completed successfully ==="

  # Clear the shard exclusion settings since the node is safely removed
  log "Clearing shard allocation exclusion settings..."
  clear_shard_exclusion "$node_name" || log "Warning: Failed to clear shard exclusion after successful completion"

  local total_time=$(( $(date +%s) - start_time ))
  log "Total time taken: ${total_time} seconds"
}

# Main execution
main() {
  if [ -z "${KB_LEAVE_MEMBER_POD_NAME:-}" ]; then
    error_exit "KB_LEAVE_MEMBER_POD_NAME environment variable is not set"
  fi

  # Run the safe scale-down process
  safe_scale_down

  # For backward compatibility and to allow the node to be removed naturally
  # we still perform the original voting exclusion logic if applicable
  if [ "$major_version" -ge 7 ]; then
    if [ "$major_version" -eq 7 ]; then
      # Extract minor version for comparison
      minor_version=$(echo "$version" | cut -d'.' -f2)
      if [ "$minor_version" -lt 8 ] 2>/dev/null; then
        url=${endpoint}/_cluster/voting_config_exclusions/$KB_LEAVE_MEMBER_POD_NAME
      else
        url=${endpoint}/_cluster/voting_config_exclusions?node_names=$KB_LEAVE_MEMBER_POD_NAME
      fi
    else
      url=${endpoint}/_cluster/voting_config_exclusions?node_names=$KB_LEAVE_MEMBER_POD_NAME
    fi
    curl ${common_options} -v -X POST $url || log "Voting exclusion already set during safe scale-down"
  else
    log "ES version $major_version does not support voting_config_exclusions API"
  fi
}

# Cleanup function
cleanup() {
  local exit_code=$?
  log "Cleanup function called with exit code: $exit_code"
  if [ $exit_code -ne 0 ]; then
    log "Script exited with error code $exit_code, attempting cleanup..."
    # Try to clear shard exclusions on failure
    if [ -n "${KB_LEAVE_MEMBER_POD_NAME:-}" ]; then
      clear_shard_exclusion "$KB_LEAVE_MEMBER_POD_NAME" || log "Failed to clear shard exclusions during cleanup"
    fi
  else
    # Even on successful exit, ensure we clear the exclusion settings
    log "Script completed successfully, clearing shard exclusions..."
    if [ -n "${KB_LEAVE_MEMBER_POD_NAME:-}" ]; then
      clear_shard_exclusion "$KB_LEAVE_MEMBER_POD_NAME" || log "Failed to clear shard exclusions after success"
    fi
  fi
  log "Cleanup completed"
  exit $exit_code
}

# Set trap for cleanup
trap cleanup EXIT

# Also trap common signals that might cause script termination
trap cleanup INT TERM

# Run main function
main