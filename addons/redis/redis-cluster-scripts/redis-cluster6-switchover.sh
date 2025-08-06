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
#
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
# shellcheck disable=SC2153
# shellcheck disable=SC1090
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

load_redis_cluster_common_utils() {
  # the common.sh and redis-cluster-common.sh scripts are defined in the redis-cluster-scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/common.sh"
  redis_cluster_common_library_file="/scripts/redis-cluster-common.sh"
  source "${kblib_common_library_file}"
  source "${redis_cluster_common_library_file}"
}

check_environment_exist() {
  local required_vars=(
    "CURRENT_SHARD_POD_NAME_LIST"
    "CURRENT_SHARD_POD_FQDN_LIST"
  )

  for var in "${required_vars[@]}"; do
    if is_empty "${!var}"; then
      echo "Error: Required environment variable $var is not set." >&2
      return 1
    fi
  done

  if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
    echo "switchover not triggered for primary, nothing to do, exit 0"
    exit 0
  fi
}

init_redis_cluster_service_port() {
  service_port=6379
  if [ -n "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
  fi
}

get_current_shard_primary() {
  local host=$1
  local port=$2
  local master_info
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    master_info=$(redis-cli -h $host -p $port info replication)
  else
    master_info=$(redis-cli -h $host -p $port -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  set_xtrace_when_ut_mode_false

  local master_host
  local master_port

  master_host=$(echo "$master_info" | grep "master_host:" | cut -d':' -f2 | tr -d '[:space:]')
  master_port=$(echo "$master_info" | grep "master_port:" | cut -d':' -f2 | tr -d '[:space:]')

  if is_empty "$master_host"|| is_empty "$master_port"; then
    return 1
  fi

  echo "$master_host:$master_port"
}

get_all_shards_master() {
  local host=$1
  local port=$2
  local cluster_nodes_info
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    cluster_nodes_info=$(redis-cli -h $host -p $port cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h $host -p $port -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set_xtrace_when_ut_mode_false

  echo "$cluster_nodes_info" | grep "master" | while read -r line; do
    node_addr=$(echo "$line" | cut -d' ' -f2 | cut -d'@' -f1)
    echo "$node_addr"
  done
}

do_switchover() {
  candidate_pod=$1
  candidate_pod_fqdn=$2
  candidate_pod_ip=$(getent hosts "$candidate_pod_fqdn" | awk '{ print $1 }')

  # check candidate pod is ready and has the role of secondary
  role=$(check_redis_role "$candidate_pod_fqdn" $service_port)
  if ! equals "$role" "secondary"; then
    echo "Error: Candidate pod $candidate_pod is not a secondary" >&2
    return 1
  fi

  # get current shard primary
  current_shard_primary=$(get_current_shard_primary "$candidate_pod_fqdn" $service_port)
  if is_empty "$current_shard_primary"; then
    echo "Error: Could not determine current shard primary for $candidate_pod" >&2
    return 1
  fi

  # check cluster health from current shard primary
  if ! check_slots_covered "$current_shard_primary" $service_port; then
    echo "Error: Cluster health check failed" >&2
    return 1
  fi

  # check if candidate is known by all the shards primary
  current_shard_primary_host=$(echo "$current_shard_primary" | cut -d':' -f1)
  current_shard_primary_port=$(echo "$current_shard_primary" | cut -d':' -f2)
  if is_empty "$current_shard_primary_host" || is_empty "$current_shard_primary_port"; then
    echo "Error: Could not determine current shard primary host and port" >&2
    return 1
  fi
  primaries=$(get_all_shards_master "$current_shard_primary_host" $current_shard_primary_port)
  for primary in $primaries; do
    primary_host=$(echo "$primary" | cut -d':' -f1)
    primary_port=$(echo "$primary" | cut -d':' -f2)
    if ! check_node_in_cluster_with_retry "$primary_host" $primary_port "$candidate_pod_ip"; then
      echo "Error: Candidate $candidate_pod is not known by shard $primary" >&2
      return 1
    fi
  done

  # do switchover
  echo "Starting switchover to $candidate_pod"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    result=$(redis-cli -h "$candidate_pod_fqdn" -p $service_port cluster failover)
  else
    result=$(redis-cli -h "$candidate_pod_fqdn" -p $service_port -a "$REDIS_DEFAULT_PASSWORD" cluster failover)
  fi
  set_xtrace_when_ut_mode_false
  if [ "$result" != "OK" ]; then
    echo "Error: Cluster Failover command failed with result: $result" >&2
    return 1
  fi

  # check switchover result
  max_attempts=60
  attempt=0
  while [ $attempt -lt $max_attempts ]; do
    role=$(check_redis_role "$candidate_pod_fqdn" $service_port)
    if [ "$role" = "primary" ]; then
      echo "Switchover successful: $candidate_pod is now primary"
      return 0
    fi
    sleep 2
    ((attempt++))
  done

  echo "Error: Switchover verification timeout" >&2
  return 1
}

switchover_without_candidate() {
  candidate_pod=""
  candidate_pod_fqdn=""
  # get the one of secondary pod of current shard
  # TODO: get the most suitable secondary pod which has the lowest latency
  IFS=',' read -ra PODS <<< "$CURRENT_SHARD_POD_NAME_LIST"
  for pod_name in "${PODS[@]}"; do
    local pod_fqdn
    pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$pod_name") || {
      echo "Failed to get FQDN for pod: $pod_name" >&2
      return 1
    }
    role=$(check_redis_role "$pod_fqdn" $service_port)
    if [ "$role" = "secondary" ]; then
      candidate_pod=$pod_name
      candidate_pod_fqdn=$pod_fqdn
      break
    fi
  done

  if is_empty "$candidate_pod"; then
    echo "Error: No eligible secondary found in pod list: $CURRENT_SHARD_POD_NAME_LIST" >&2
    return 1
  fi

  # do switchover
  do_switchover "$candidate_pod" "$candidate_pod_fqdn" || return 1
}

switchover_with_candidate() {
  # check KB_SWITCHOVER_CANDIDATE_FQDN and KB_SWITCHOVER_CANDIDATE_NAME are not empty
  if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN" || is_empty "$KB_SWITCHOVER_CANDIDATE_NAME"; then
    echo "KB_SWITCHOVER_CANDIDATE_NAME or KB_SWITCHOVER_CANDIDATE_FQDN is empty" >&2
    return 1
  fi

  # do switchover
  do_switchover "$KB_SWITCHOVER_CANDIDATE_NAME" "$KB_SWITCHOVER_CANDIDATE_FQDN" || return 1
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_redis_cluster_common_utils
check_environment_exist || exit 1
init_redis_cluster_service_port
if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
  switchover_without_candidate || exit 1
else
  switchover_with_candidate || exit 1
fi