#!/bin/bash

# shellcheck disable=SC2153
# shellcheck disable=SC2207
# shellcheck disable=SC2034

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
ut_mode="false"
test || __() {
 # when running in non-unit test mode, set the options "set -ex".
 set -ex;
}

retry_times=3
check_ready_times=30
retry_delay_second=2

# usage: sleep_random_second <max_time> <min_time>
sleep_random_second() {
  local max_time="$1"
  local min_time="$2"
  local random_time=$((RANDOM % (max_time - min_time + 1) + min_time))
  echo "Sleeping for $random_time seconds"
  sleep "$random_time"
}

## the component names of all shard
## the value format of ALL_SHARDS_COMPONENT_SHORT_NAMES is like "shard-98x:shard-98x,shard-cq7:shard-cq7,shard-hy7:shard-hy7"
## return the component names of all shards with the format "shard-98x,shard-cq7,shard-hy7"
get_all_shards_components() {
  local all_shards_components
  if is_empty "$ALL_SHARDS_COMPONENT_SHORT_NAMES"; then
    echo "Error: Required environment variable ALL_SHARDS_COMPONENT_SHORT_NAMES is not set."
    exit 1
  fi
  all_shards_component_shortname_pairs=$(split "$ALL_SHARDS_COMPONENT_SHORT_NAMES" ",")
  for pair in $all_shards_component_shortname_pairs; do
    shard_name=$(split "$pair" ":")
    all_shards_components="$all_shards_components,$shard_name"
  done
  echo "$all_shards_components"
}

## the pod names of all shard, there are some environment variables name prefix with "ALL_SHARDS_POD_NAME_LIST" and
## suffix with the shard name, like "ALL_SHARDS_POD_NAME_LIST_SHARD_98X", "ALL_SHARDS_POD_NAME_LIST_SHARD_CQ7", "ALL_SHARDS_POD_NAME_LIST_SHARD_HY7"
## - ALL_SHARDS_POD_NAME_LIST_SHARD_98X="redis-shard-98x-0,redis-shard-98x-1"
## - ALL_SHARDS_POD_NAME_LIST_SHARD_CQ7="redis-shard-cq7-0,redis-shard-cq7-1"
## - ALL_SHARDS_POD_NAME_LIST_SHARD_HY7="redis-shard-hy7-0,redis-shard-hy7-1"
get_all_shards_pods() {
  ## list all Envs name prefix with ALL_SHARDS_POD_NAME_LIST and get them value combined with ","
  local all_shards_pods
  envs=$(env | grep "^ALL_SHARDS_POD_NAME_LIST" | awk -F '=' '{print $2}')
  while read -r line; do
    ## remove the \n at the end of the string
    line=$(echo "$line" | tr -d '\n')

    ## remove the , at the beginning of the string
    if is_empty "$all_shards_pods"; then
      all_shards_pods="${line}"
      continue
    fi
    all_shards_pods="$all_shards_pods,${line}"
  done <<< "$envs"
}

shutdown_redis_server() {
  local service_port="$1"
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    redis-cli -h 127.0.0.1 -p "$service_port" -a "$REDIS_DEFAULT_PASSWORD" shutdown
  else
    redis-cli -h 127.0.0.1 -p "$service_port" shutdown
  fi
  set_xtrace_when_ut_mode_false
  echo "shutdown redis server succeeded!"
}

check_redis_server_ready() {
  unset_xtrace_when_ut_mode_false
  local max_retry=10
  local retry_interval=5
  check_ready_cmd="redis-cli -h 127.0.0.1 -p $service_port ping"
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    check_ready_cmd="redis-cli -h 127.0.0.1 -p $service_port -a $REDIS_DEFAULT_PASSWORD ping"
  fi
  set_xtrace_when_ut_mode_false
  output=$($check_ready_cmd)
  status=$?
  if [ $status -ne 0 ] || [ "$output" != "PONG" ] ; then
    echo "Failed to execute the check ready command: $check_ready_cmd" >&2
    return 1
  fi
}

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

parse_advertised_port() {
  local pod_name="$1"
  local advertised_ports="$2"
  local pod_name_ordinal
  local found=false

  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  IFS=',' read -ra ports_array <<< "$advertised_ports"
  for entry in "${ports_array[@]}"; do
    IFS=':' read -ra parts <<< "$entry"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    local svc_name_ordinal

    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "$port"
      found=true
      return 0
    fi
  done

  if [[ "$found" == false ]]; then
    return 1
  fi
}

send_cluster_meet() {
  local primary_endpoint="$1"
  local primary_port="$2"
  local announce_ip="$3"
  local announce_port="$4"
  local announce_bus_port="$5"

  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    meet_command="redis-cli -h $primary_endpoint -p $primary_port cluster meet $announce_ip $announce_port $announce_bus_port"
    logging_mask_meet_command="$meet_command"
  else
    meet_command="redis-cli -h $primary_endpoint -p $primary_port -a $REDIS_DEFAULT_PASSWORD cluster meet $announce_ip $announce_port $announce_bus_port"
    logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "check and correct other primary nodes meet command: $logging_mask_meet_command"
  if ! $meet_command
  then
      echo "Failed to meet the node $announce_ip:$announce_port in check_and_correct_other_primary_nodes" >&2
      return 1
  else
    echo "Meet the node $announce_ip:$announce_port successfully with new announce ip $announce_ip..." >&2
    return 0
  fi
  set_xtrace_when_ut_mode_false
}

get_cluster_info() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  unset_xtrace_when_ut_mode_false
  local command="redis-cli -h $cluster_node -p $cluster_node_port cluster info"
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    command="redis-cli -h $cluster_node -p $cluster_node_port -a $REDIS_DEFAULT_PASSWORD cluster info"
  fi
  set_xtrace_when_ut_mode_false
  cluster_info=$($command)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to execute the get cluster info command" >&2
    return 1
  fi
  echo "$cluster_info"
  return 0
}

get_cluster_nodes_info() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  unset_xtrace_when_ut_mode_false
  local command="redis-cli -h $cluster_node -p $cluster_node_port cluster nodes"
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    command="redis-cli -h $cluster_node -p $cluster_node_port -a $REDIS_DEFAULT_PASSWORD cluster nodes"
  fi
  set_xtrace_when_ut_mode_false
  cluster_nodes_info=$($command)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to execute the get cluster nodes info command" >&2
    return 1
  fi
  echo "$cluster_nodes_info"
  return 0
}

get_cluster_id() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in get_cluster_id" >&2
    return 1
  fi
  cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
  echo "$cluster_id"
  return 0
}

get_cluster_announce_ip() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in get_cluster_announce_ip" >&2
    return 1
  fi
  cluster_announce_ip=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $2}' | awk -F ':' '{print $1}')
  echo "$cluster_announce_ip"
  return 0
}

check_node_in_cluster() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  local node_name="$3"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in check_node_in_cluster" >&2
    return 1
  fi
  # if the cluster_nodes_info contains multiple lines and the node_name is in the cluster_nodes_info, return true
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -gt 1 ] && echo "$cluster_nodes_info" | grep -q "$node_name"; then
    return 0
  else
    return 1
  fi
}

send_cluster_meet_with_retry() {
  local primary_endpoint="$1"
  local primary_port="$2"
  local announce_ip="$3"
  local announce_port="$4"
  local announce_bus_port="$5"
  send_cluster_meet_result=$(call_func_with_retry $retry_times $retry_delay_second send_cluster_meet "$primary_endpoint" "$primary_port" "$announce_ip" "$announce_port" "$announce_bus_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to meet the node $announce_ip:$announce_port in check_and_correct_other_primary_nodes after retry" >&2
    return 1
  fi
  return 0
}

get_cluster_nodes_info_with_retry() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  # call the get_cluster_nodes_info function with call_func_with_retry function and get the output
  cluster_nodes_info=$(call_func_with_retry $retry_times $retry_delay_second get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get the cluster nodes info of the cluster node $cluster_node:$cluster_node_port after retry" >&2
    return 1
  fi
  echo "$cluster_nodes_info"
  return 0
}

get_cluster_id_with_retry() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  # call the execute_get_cluster_id_command function with call_func_with_retry function and get the output
  cluster_id=$(call_func_with_retry $retry_times $retry_delay_second get_cluster_id "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get the cluster id of the cluster node $cluster_node:$cluster_node_port after retry" >&2
    return 1
  fi
  echo "$cluster_id"
  return 0
}

get_cluster_announce_ip_with_retry() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  # call the execute_get_cluster_announce_ip_command function with call_func_with_retry function and get the output
  cluster_announce_ip=$(call_func_with_retry $retry_times $retry_delay_second get_cluster_announce_ip "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get the cluster announce ip of the cluster node $cluster_node:$cluster_node_port after retry" >&2
    return 1
  fi
  echo "$cluster_announce_ip"
  return 0
}

check_node_in_cluster_with_retry() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  local node_name="$3"
  # call the execute_check_node_in_cluster_command function with call_func_with_retry function and get the output
  check_result=$(call_func_with_retry $retry_times $retry_delay_second check_node_in_cluster "$cluster_node" "$cluster_node_port" "$node_name")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to check the node $node_name in the cluster node $cluster_node:$cluster_node_port after retry" >&2
    return 1
  fi
  return 0
}

check_redis_server_ready_with_retry() {
  # call the execute_check_redis_server_ready_command function with call_func_with_retry function and get the output
  check_result=$(call_func_with_retry $check_ready_times $retry_delay_second check_redis_server_ready)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to check the redis server ready after retry" >&2
    return 1
  fi
  return 0
}

# check redis cluster all slots are covered
check_slots_covered() {
  # cluster_node_endpoint_wth_port is the target node endpoint with port, for example 172.0.0.1:6379
  local node_endpoint_wth_port="$1"
  local cluster_service_port="$2"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    check=$(redis-cli --cluster check "$node_endpoint_wth_port" -p "$cluster_service_port")
  else
    check=$(redis-cli --cluster check "$node_endpoint_wth_port" -p "$cluster_service_port" -a "$REDIS_DEFAULT_PASSWORD" )
  fi
  set_xtrace_when_ut_mode_false
  if contains "$check" "All 16384 slots covered"; then
    return 0
  else
    return 1
  fi
}

# check if the cluster has been initialized
check_cluster_initialized() {
  local cluster_node_list="$1"
  # all cluster node share the same service port
  local cluster_node_service_port="$2"
  if is_empty "$cluster_node_list" || is_empty "$cluster_node_service_port"; then
    echo "Error: Required environment variable cluster_node_list or cluster_node_service_port  is not set."
    exit 1
  fi

  for pod_ip in $(echo "$cluster_node_list" | tr ',' ' '); do
    cluster_info=$(get_cluster_info "$pod_ip" "$cluster_node_service_port")
    status=$?
    if [ $status -ne 0 ]; then
      echo "Failed to get cluster info in check_cluster_initialized" >&2
      exit 1
    fi
    cluster_state=$(echo "$cluster_info" | grep -oP '(?<=cluster_state:)[^\s]+')
    if is_empty "$cluster_state" || equals "$cluster_state" "ok"; then
      echo "Redis Cluster already initialized"
      return 0
    fi
  done
  echo "Redis Cluster not initialized" >&2
  return 1
}

build_redis_cluster_create_command() {
  local primary_nodes="$1"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    initialize_command="redis-cli --cluster create $primary_nodes --cluster-yes"
    logging_mask_initialize_command="$initialize_command"
  else
    initialize_command="redis-cli --cluster create $primary_nodes -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
    logging_mask_initialize_command="${initialize_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "initialize cluster command: $logging_mask_initialize_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$initialize_command"
}

build_secondary_replicated_command() {
  local secondary_endpoint_with_port="$1"
  local mapping_primary_endpoint_with_port="$2"
  local mapping_primary_cluster_id="$3"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    replicated_command="redis-cli --cluster add-node $secondary_endpoint_with_port $mapping_primary_endpoint_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id"
    logging_mask_replicated_command="$replicated_command"
  else
    replicated_command="redis-cli --cluster add-node $secondary_endpoint_with_port $mapping_primary_endpoint_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id -a $REDIS_DEFAULT_PASSWORD"
    logging_mask_replicated_command="${replicated_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "initialize cluster secondary add-node command: $logging_mask_replicated_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$replicated_command"
}

build_scale_out_shard_primary_join_command() {
  local scale_out_shard_default_primary_endpoint_with_port="$1"
  local exist_available_node="$2"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    add_node_command="redis-cli --cluster add-node $scale_out_shard_default_primary_endpoint_with_port $exist_available_node"
    logging_mask_add_node_command="$add_node_command"
  else
    add_node_command="redis-cli --cluster add-node $scale_out_shard_default_primary_endpoint_with_port $exist_available_node -a $REDIS_DEFAULT_PASSWORD"
    logging_mask_add_node_command="${add_node_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "scale out shard primary add-node command: $logging_mask_add_node_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$add_node_command"
}

build_reshard_command() {
  local primary_node_with_port="$1"
  local mapping_primary_cluster_id="$2"
  local slots_per_shard="$3"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    reshard_command="redis-cli --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard --cluster-yes"
    logging_mask_reshard_command="$reshard_command"
  else
    reshard_command="redis-cli --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
    logging_mask_reshard_command="${reshard_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "scale out shard reshard command: $logging_mask_reshard_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$reshard_command"
}

create_redis_cluster() {
  local primary_nodes="$1"
  initialize_command=$(build_redis_cluster_create_command "$primary_nodes")
  if ! $initialize_command; then
    echo "Failed to create Redis Cluster" >&2
    return 1
  fi
  return 0
}

secondary_replicated_to_primary() {
  local secondary_endpoint_with_port="$1"
  local mapping_primary_endpoint_with_port="$2"
  local mapping_primary_cluster_id="$3"
  replicated_command=$(build_secondary_replicated_command "$secondary_endpoint_with_port" "$mapping_primary_endpoint_with_port" "$mapping_primary_cluster_id")
  replicated_output=$($replicated_command)
  replicated_exit_code=$?
  if [ $replicated_exit_code -ne 0 ]; then
    echo "Failed to replicate the secondary node $secondary_endpoint_with_port to the primary node $mapping_primary_endpoint_with_port" >&2
    return 1
  fi
  echo "$replicated_output"
  return 0
}

scale_out_shard_primary_join_cluster() {
  local scale_out_shard_default_primary_endpoint_with_port="$1"
  local exist_available_node="$2"
  add_node_command=$(build_scale_out_shard_primary_join_command "$scale_out_shard_default_primary_endpoint_with_port" "$exist_available_node")
  if ! $add_node_command; then
    echo "Failed to add the node $scale_out_shard_default_primary_endpoint_with_port to the cluster" >&2
    return 1
  fi
  return 0
}

scale_out_shard_reshard() {
  local primary_node_with_port="$1"
  local mapping_primary_cluster_id="$2"
  local slots_per_shard="$3"
  reshard_command=$(build_reshard_command "$primary_node_with_port" "$mapping_primary_cluster_id" "$slots_per_shard")
  if ! $reshard_command; then
    echo "Failed to reshard the cluster" >&2
    return 1
  fi
  return 0
}