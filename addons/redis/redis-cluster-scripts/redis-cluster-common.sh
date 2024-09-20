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
    echo "Failed to execute the get cluster id command: $command" >&2
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
    echo "Failed to get cluster nodes info in get_cluster_id: $command" >&2
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
    echo "Failed to get cluster nodes info in get_cluster_announce_ip: $command" >&2
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
    echo "Failed to get cluster nodes info in check_node_in_cluster: $command" >&2
    return 1
  fi
  # if the cluster_nodes_info contains multiple lines and the node_name is in the cluster_nodes_info, return true
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -gt 1 ] && echo "$cluster_nodes_info" | grep -q "$node_name"; then
    return 0
  else
    return 1
  fi
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