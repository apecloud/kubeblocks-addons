#!/bin/bash

# shellcheck disable=SC2086
set -ex

check_environment_exist() {
  if [ -z "$KB_POD_LIST" ]; then
    echo "Error: Required environment variable KB_POD_LIST: $KB_POD_LIST is not set."
    exit 1
  fi
}

init_redis_cluster_service_port() {
  service_port=6379
  if [ -n "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
  fi
}

check_redis_role() {
  local host=$1
  local port=$2
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    role_info=$(redis-cli -h $host -p $port info replication)
  else
    role_info=$(redis-cli -h $host -p $port -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  set -x

  if echo "$role_info" | grep -q "^role:master"; then
    echo "primary"
  elif echo "$role_info" | grep -q "^role:slave"; then
    echo "secondary"
  else
    echo "unknown"
  fi
}

redis_cluster_check() {
  # check redis cluster all slots are covered
  local cluster_node_with_port_to_check="$1"
  local current_server_port="$2"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    check=$(redis-cli --cluster check "$cluster_node_with_port_to_check" -p "$current_server_port")
  else
    check=$(redis-cli --cluster check "$cluster_node_with_port_to_check" -p "$current_server_port" -a "$REDIS_DEFAULT_PASSWORD" )
  fi
  set -x
  if [[ $check =~ "All 16384 slots covered" ]]; then
    true
  else
    false
  fi
}

is_node_in_cluster() {
  local random_node_endpoint="$1"
  local random_node_port="$2"
  local node_name="$3"

  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$random_node_endpoint" -p "$random_node_port" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$random_node_endpoint" -p "$random_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x

  # if the cluster_nodes_info contains multiple lines and the node_name is in the cluster_nodes_info, return true
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -gt 1 ] && echo "$cluster_nodes_info" | grep -q "$node_name"; then
    true
  else
    false
  fi
}

get_current_shard_primary() {
  local host=$1
  local port=$2
  local master_info
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    master_info=$(redis-cli -h $host -p $port info replication)
  else
    master_info=$(redis-cli -h $host -p $port -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  set -x

  local master_host
  local master_port

  master_host=$(echo "$master_info" | grep "master_host:" | cut -d':' -f2 | tr -d '[:space:]')
  master_port=$(echo "$master_info" | grep "master_port:" | cut -d':' -f2 | tr -d '[:space:]')

  if [ -z "$master_host" ] || [ -z "$master_port" ]; then
    return 1
  fi

  echo "$master_host:$master_port"
}

get_all_shards_master() {
  local host=$1
  local port=$2
  local cluster_nodes_info
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h $host -p $port cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h $host -p $port -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x

  echo "$cluster_nodes_info" | grep "master" | while read -r line; do
    node_addr=$(echo "$line" | cut -d' ' -f2 | cut -d'@' -f1)
    echo "$node_addr"
  done
}

do_switchover() {
  candidate_pod=$1
  candidate_pod_fqdn=$2

  # check candidate pod is ready and has the role of secondary
  role=$(check_redis_role "$candidate_pod_fqdn" $service_port)
  if [ "$role" = "primary" ]; then
    echo "Info: Candidate pod $candidate_pod is already a primary"
    exit 0
  fi
  if [ "$role" != "secondary" ]; then
    echo "Error: Candidate pod $candidate_pod is not a secondary"
    exit 1
  fi

  # get current shard primary
  current_shard_primary=$(get_current_shard_primary "$candidate_pod_fqdn" $service_port)
  if [ -z "$current_shard_primary" ]; then
    echo "Error: Could not determine current shard primary for $candidate_pod"
    exit 1
  fi

  # check cluster health from current shard primary
  if ! redis_cluster_check "$current_shard_primary" $service_port; then
    echo "Error: Cluster health check failed"
    exit 1
  fi

  # check if candidate is known by all the shards primary
  current_shard_primary_host=$(echo "$current_shard_primary" | cut -d':' -f1)
  current_shard_primary_port=$(echo "$current_shard_primary" | cut -d':' -f2)
  if [ -z "$current_shard_primary_host" ] || [ -z "$current_shard_primary_port" ]; then
    echo "Error: Could not determine current shard primary host and port"
    exit 1
  fi
  primaries=$(get_all_shards_master "$current_shard_primary_host" $current_shard_primary_port)
  for primary in $primaries; do
    primary_host=$(echo "$primary" | cut -d':' -f1)
    primary_port=$(echo "$primary" | cut -d':' -f2)
    if ! is_node_in_cluster "$primary_host" $primary_port "$candidate_pod"; then
      echo "Error: Candidate $candidate_pod is not known by shard $primary"
      exit 1
    fi
  done

  # do switchover
  echo "Starting switchover to $candidate_pod"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    result=$(redis-cli -h "$candidate_pod_fqdn" -p $service_port cluster failover)
  else
    result=$(redis-cli -h "$candidate_pod_fqdn" -p $service_port -a "$REDIS_DEFAULT_PASSWORD" cluster failover)
  fi
  set -x
  if [ "$result" != "OK" ]; then
    echo "Error: Cluster Failover command failed with result: $result"
    exit 1
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

  echo "Error: Switchover verification timeout"
  exit 1
}

switchover_without_candidate() {
  candidate_pod=""
  candidate_pod_fqdn=""
  # get the one of secondary pod of current shard
  # TODO: get the most suitable secondary pod which has the lowest latency
  IFS=',' read -ra PODS <<< "$KB_POD_LIST"
  for pod in "${PODS[@]}"; do
    pod_fqdn="$pod.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    role=$(check_redis_role "$pod_fqdn" $service_port)
    if [ "$role" = "secondary" ]; then
      candidate_pod=$pod
      candidate_pod_fqdn=$pod_fqdn
      break
    fi
  done

  if [ -z "$candidate_pod" ]; then
    echo "Error: No eligible secondary found in pod list: $KB_POD_LIST"
    exit 1
  fi

  # do switchover
  do_switchover "$candidate_pod" "$candidate_pod_fqdn"
}

switchover_with_candidate() {
  # check KB_SWITCHOVER_CANDIDATE_FQDN and KB_SWITCHOVER_CANDIDATE_NAME are not empty
  if [ -z "$KB_SWITCHOVER_CANDIDATE_FQDN" ] ||  [ -z "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
    echo "KB_SWITCHOVER_CANDIDATE_NAME or KB_SWITCHOVER_CANDIDATE_FQDN is empty" >&2
    exit 1
  fi

  # do switchover
  do_switchover "$KB_SWITCHOVER_CANDIDATE_NAME" "$KB_SWITCHOVER_CANDIDATE_FQDN"
}

# main
check_environment_exist
init_redis_cluster_service_port
if [ -z "$KB_SWITCHOVER_CANDIDATE_FQDN" ]; then
  switchover_without_candidate
else
  switchover_with_candidate
fi