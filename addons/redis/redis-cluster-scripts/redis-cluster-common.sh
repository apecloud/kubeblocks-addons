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

# usage: sleep_random_second_when_ut_mode_false <max_time> <min_time>
sleep_random_second_when_ut_mode_false() {
  if [ "false" == "$ut_mode" ]; then
    local max_time="$1"
    local min_time="$2"
    local random_time=$((RANDOM % (max_time - min_time + 1) + min_time))
    echo "Sleeping for $random_time seconds"
    sleep "$random_time"
  fi
}

## the component names of all shard
## the value format of ALL_SHARDS_COMPONENT_SHORT_NAMES is like "shard-98x:shard-98x,shard-cq7:shard-cq7,shard-hy7:shard-hy7"
## return the component names of all shards with the format "shard-98x,shard-cq7,shard-hy7"
get_all_shards_components() {
  local all_shards_components=""
  if is_empty "$ALL_SHARDS_COMPONENT_SHORT_NAMES"; then
    echo "Error: Required environment variable ALL_SHARDS_COMPONENT_SHORT_NAMES is not set." >&2
    return 1
  fi
  IFS=',' read -ra all_shards_component_shortname_pairs <<< "$ALL_SHARDS_COMPONENT_SHORT_NAMES"
  for pair in "${all_shards_component_shortname_pairs[@]}"; do
    IFS=':' read -r shard_name _ <<< "$pair"
    all_shards_components="${all_shards_components},${shard_name}"
  done
  all_shards_components="${all_shards_components#,}"
  echo "$all_shards_components"
  return 0
}

## the pod names of all shard, there are some environment variables name prefix with "ALL_SHARDS_POD_NAME_LIST" and
## suffix with the shard name, like "ALL_SHARDS_POD_NAME_LIST_SHARD_98X", "ALL_SHARDS_POD_NAME_LIST_SHARD_CQ7", "ALL_SHARDS_POD_NAME_LIST_SHARD_HY7"
## - ALL_SHARDS_POD_NAME_LIST_SHARD_98X="redis-shard-98x-0,redis-shard-98x-1"
## - ALL_SHARDS_POD_NAME_LIST_SHARD_CQ7="redis-shard-cq7-0,redis-shard-cq7-1"
## - ALL_SHARDS_POD_NAME_LIST_SHARD_HY7="redis-shard-hy7-0,redis-shard-hy7-1"
## return the pod names of all shards combined with ","
get_all_shards_pods() {
  ## list all Envs name prefix with ALL_SHARDS_POD_NAME_LIST and get them value combined with ","
  local envs
  local all_shards_pods=""
  envs=$(env | grep "^ALL_SHARDS_POD_NAME_LIST" | sort)
  while IFS='=' read -r env_name env_value; do
    if ! is_empty "$env_value"; then
      if is_empty "$all_shards_pods"; then
        all_shards_pods="$env_value"
      else
        all_shards_pods="$all_shards_pods,$env_value"
      fi
    fi
  done <<< "$envs"
  echo "$all_shards_pods"
  return 0
}

## the pod fqdn list for all shard pod, it will generate a set of variables with the shard name suffix like:
## - ALL_SHARDS_POD_FQDN_LIST_SHARD_98X="redis-shard-98x-0.redis-shard-98x-headless.default.cluster.local,redis-shard-98x-1.redis-shard-98x-headless.default.cluster.local"
## - ALL_SHARDS_POD_FQDN_LIST_SHARD_CQ7="redis-shard-cq7-0.redis-shard-cq7-headless.default.cluster.local,redis-shard-cq7-1.redis-shard-cq7-headless.default.cluster.local"
## - ALL_SHARDS_POD_FQDN_LIST_SHARD_HY7="redis-shard-hy7-0.redis-shard-hy7-headless.default.cluster.local,redis-shard-hy7-1.redis-shard-hy7-headless.default.cluster.local"
## return the pod fqdn list for all shard pod combined with ","
get_all_shards_pod_fqdns() {
  ## list all Envs name prefix with ALL_SHARDS_POD_FQDN_LIST and get them value combined with ","
  local envs
  local all_shards_pod_fqdns=""
  envs=$(env | grep "^ALL_SHARDS_POD_FQDN_LIST" | sort)
  while IFS='=' read -r env_name env_value; do
    if [[ -n "$env_value" ]]; then
      if [[ -z "$all_shards_pod_fqdns" ]]; then
        all_shards_pod_fqdns="$env_value"
      else
        all_shards_pod_fqdns="$all_shards_pod_fqdns,$env_value"
      fi
    fi
  done <<< "$envs"
  echo "$all_shards_pod_fqdns"
  return 0
}

shutdown_redis_server() {
  local service_port="$1"
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p "$service_port" -a "$REDIS_DEFAULT_PASSWORD" shutdown
  else
    redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p "$service_port" shutdown
  fi
  set_xtrace_when_ut_mode_false
  echo "shutdown redis server succeeded!"
}

check_redis_server_ready() {
  unset_xtrace_when_ut_mode_false
  local host="$1"
  local port="$2"
  local max_retry=10
  local retry_interval=5
  check_ready_cmd="redis-cli $REDIS_CLI_TLS_CMD -h $host -p $port ping"
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    check_ready_cmd="redis-cli $REDIS_CLI_TLS_CMD -h $host -p $port -a $REDIS_DEFAULT_PASSWORD ping"
  fi
  logging_check_ready_cmd=${check_ready_cmd/$REDIS_DEFAULT_PASSWORD/********}
  output=$($check_ready_cmd)
  status=$?
  set_xtrace_when_ut_mode_false
  if [ $status -ne 0 ] || [ "$output" != "PONG" ] ; then
    echo "Failed to execute the check ready command: $logging_check_ready_cmd" >&2
    return 1
  fi
}

parse_advertised_svc_and_port() {
  local pod_name="$1"
  local advertised_ports="$2"
  local svc_and_port="$3"
  local pod_name_ordinal
  local found=false

  pod_name_ordinal=$(extract_obj_ordinal "$pod_name")
  IFS=',' read -ra ports_array <<< "$advertised_ports"
  for entry in "${ports_array[@]}"; do
    IFS=':' read -ra parts <<< "$entry"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    local svc_name_ordinal

    svc_name_ordinal=$(extract_obj_ordinal "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      if [[ "${svc_and_port}" == "true" ]]; then
         echo "$svc_name:$port"
      else
         echo "$port"
      fi
      found=true
      return 0
    fi
  done

  if [[ "$found" == false ]]; then
    return 1
  fi
}

get_pod_service_port_by_network_mode() {
  local target_pod_name="$1"
  local service_port=${SERVICE_PORT:-6379}
  # if redis cluster is using host network, the service port should be the host network port
  if ! is_empty "$REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT"; then
    IFS=',' read -ra port_mappings <<< "$REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT"
    for mapping in "${port_mappings[@]}"; do
      shard_name=$(echo "$mapping" | cut -d':' -f1)
      mapping_port=$(echo "$mapping" | cut -d':' -f2)
      if echo "${target_pod_name}" | grep -q "$shard_name"; then
        service_port=$mapping_port
        break
      fi
    done
  fi
  echo "$service_port"
}

send_cluster_meet() {
  local primary_endpoint="$1"
  local primary_port="$2"
  local announce_ip="$3"
  local announce_port="$4"
  local announce_bus_port="$5"

  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    meet_command="redis-cli $REDIS_CLI_TLS_CMD -h $primary_endpoint -p $primary_port cluster meet $announce_ip $announce_port $announce_bus_port"
    logging_mask_meet_command="$meet_command"
  else
    meet_command="redis-cli $REDIS_CLI_TLS_CMD -h $primary_endpoint -p $primary_port -a $REDIS_DEFAULT_PASSWORD cluster meet $announce_ip $announce_port $announce_bus_port"
    logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "check and correct other primary nodes meet command: $logging_mask_meet_command"
  if ! $meet_command
  then
      echo "Failed to meet the node $announce_ip:$announce_port in check_and_meet_other_primary_nodes" >&2
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
  local command="redis-cli $REDIS_CLI_TLS_CMD -h $cluster_node -p $cluster_node_port cluster info"
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    command="redis-cli $REDIS_CLI_TLS_CMD -h $cluster_node -p $cluster_node_port -a $REDIS_DEFAULT_PASSWORD cluster info"
  fi
  cluster_info=$($command)
  status=$?
  set_xtrace_when_ut_mode_false
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
  local command="redis-cli $REDIS_CLI_TLS_CMD -h $cluster_node -p $cluster_node_port cluster nodes"
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    command="redis-cli $REDIS_CLI_TLS_CMD -h $cluster_node -p $cluster_node_port -a $REDIS_DEFAULT_PASSWORD cluster nodes"
  fi
  cluster_nodes_info=$($command)
  status=$?
  set_xtrace_when_ut_mode_false
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
  local pod_fqdn="$3"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in get_cluster_id" >&2
    return 1
  fi
  if [ -n "${pod_fqdn}" ]; then
    cluster_id=$(echo "$cluster_nodes_info" | grep "${pod_fqdn}" | awk '{print $1}')
  else
    cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
  fi
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
  send_cluster_meet_result=$(call_func_with_retry $retry_times 10 send_cluster_meet "$primary_endpoint" "$primary_port" "$announce_ip" "$announce_port" "$announce_bus_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to meet the node $announce_ip:$announce_port in check_and_meet_other_primary_nodes after retry" >&2
    return 1
  fi
  return 0
}

get_cluster_info_with_retry() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  # call the get_cluster_info function with call_func_with_retry function and get the output
  cluster_info=$(call_func_with_retry $retry_times $retry_delay_second get_cluster_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get the cluster info of the cluster node $cluster_node:$cluster_node_port after retry" >&2
    return 1
  fi
  echo "$cluster_info"
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
  local pod_fqdn="$3"
  # call the execute_get_cluster_id_command function with call_func_with_retry function and get the output
  cluster_id=$(call_func_with_retry $retry_times $retry_delay_second get_cluster_id "$cluster_node" "$cluster_node_port" "${pod_fqdn}")
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
  local host="$1"
  local port="$2"
  # call the execute_check_redis_server_ready_command function with call_func_with_retry function and get the output
  check_result=$(call_func_with_retry $check_ready_times $retry_delay_second check_redis_server_ready "$host" "$port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to check the redis server ready after retry" >&2
    return 1
  fi
  return 0
}

classify_redis_cluster_check_output() {
  local check_rc="$1"
  local check_output="$2"

  if contains "$check_output" "[WARNING] The following slots are open" || \
     contains "$check_output" "has slots in importing state" || \
     contains "$check_output" "has slots in migrating state" || \
     contains "$check_output" "Not all 16384 slots are covered by nodes"; then
    echo "open-or-uncovered"
    return 0
  fi

  if contains "$check_output" "All 16384 slots covered" && \
     contains "$check_output" "Nodes don't agree about configuration"; then
    echo "views-disagreement"
    return 0
  fi

  if [ "$check_rc" -eq 0 ] && \
     contains "$check_output" "All 16384 slots covered" && \
     ! contains "$check_output" "[ERR]"; then
    echo "stable"
    return 0
  fi

  echo "probe-error"
}

inspect_redis_cluster_check() {
  # node_endpoint_with_port is the target node endpoint with port, for example 172.0.0.1:6379
  local node_endpoint_with_port="$1"
  local cluster_service_port="$2"
  local output
  local check_rc

  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    if output=$(redis-cli $REDIS_CLI_TLS_CMD --cluster check "$node_endpoint_with_port" -p "$cluster_service_port" 2>&1); then
      check_rc=0
    else
      check_rc=$?
    fi
  else
    if output=$(redis-cli $REDIS_CLI_TLS_CMD --cluster check "$node_endpoint_with_port" -p "$cluster_service_port" -a "$REDIS_DEFAULT_PASSWORD" 2>&1); then
      check_rc=0
    else
      check_rc=$?
    fi
  fi
  set_xtrace_when_ut_mode_false

  redis_cluster_check_output="$output"
  redis_cluster_check_rc="$check_rc"
  redis_cluster_check_state=$(classify_redis_cluster_check_output "$check_rc" "$output")
}

# check redis cluster all slots are covered and every node view is stable
check_slots_covered() {
  local node_endpoint_with_port="$1"
  local cluster_service_port="$2"

  inspect_redis_cluster_check "$node_endpoint_with_port" "$cluster_service_port"
  if [ "$redis_cluster_check_state" = "stable" ]; then
    return 0
  fi

  echo "Redis Cluster check is not stable (state=$redis_cluster_check_state, rc=$redis_cluster_check_rc):" >&2
  echo "$redis_cluster_check_output" >&2
  return 1
}

fix_cluster_slots() {
  local node_endpoint_with_port="$1"
  local cluster_service_port="$2"
  local fix_yes_input
  local fix_yes_count
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    fix_command="redis-cli $REDIS_CLI_TLS_CMD --cluster fix $node_endpoint_with_port -p $cluster_service_port --cluster-yes"
    logging_mask_fix_command="$fix_command"
  else
    fix_command="redis-cli $REDIS_CLI_TLS_CMD --cluster fix $node_endpoint_with_port -p $cluster_service_port --cluster-yes -a $REDIS_DEFAULT_PASSWORD"
    logging_mask_fix_command="${fix_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  fix_yes_input=""
  fix_yes_count=0
  while [ "$fix_yes_count" -lt 128 ]; do
    fix_yes_input="${fix_yes_input}yes\n"
    fix_yes_count=$((fix_yes_count + 1))
  done
  echo "fix Redis Cluster slots command: printf yes... | $logging_mask_fix_command" >&2
  if ! printf "%b" "$fix_yes_input" | $fix_command; then
    set_xtrace_when_ut_mode_false
    echo "Failed to fix Redis Cluster slots for $node_endpoint_with_port" >&2
    return 1
  fi
  set_xtrace_when_ut_mode_false
  return 0
}

count_node_slots() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  local node_cluster_id="$3"
  local cluster_nodes_info
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in count_node_slots" >&2
    return 1
  fi

  echo "$cluster_nodes_info" | awk -v node_id="$node_cluster_id" '
    $1 == node_id {
      count = 0
      for (i = 9; i <= NF; i++) {
        if ($i ~ /^[0-9]+$/) {
          count += 1
        } else if ($i ~ /^[0-9]+-[0-9]+$/) {
          split($i, range, "-")
          count += range[2] - range[1] + 1
        }
      }
      print count
      found = 1
    }
    END {
      if (!found) {
        exit 1
      }
    }'
}

# check if the cluster has been initialized
check_cluster_initialized() {
  local cluster_pod_fqdn_list="$1"
  if is_empty "$cluster_pod_fqdn_list"; then
    echo "Error: Required environment variable cluster_pod_fqdn_list is not set." >&2
    return 1
  fi

  local service_port
  for pod_fqdn in $(echo "$cluster_pod_fqdn_list" | tr ',' ' '); do
    pod_name=${pod_fqdn%%.*}
    service_port=$(get_pod_service_port_by_network_mode "${pod_name}")
    cluster_info=$(get_cluster_info_with_retry "$pod_fqdn" "$service_port")
    status=$?
    if [ $status -ne 0 ]; then
      echo "Failed to get cluster info in check_cluster_initialized" >&2
      return 1
    fi
    cluster_state=$(echo "$cluster_info" | awk -F: '/cluster_state/{print $2}' | tr -d '[:space:]')
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
    initialize_command="redis-cli $REDIS_CLI_TLS_CMD --cluster create $primary_nodes --cluster-yes"
    logging_mask_initialize_command="$initialize_command"
  else
    initialize_command="redis-cli $REDIS_CLI_TLS_CMD --cluster create $primary_nodes -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
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
    replicated_command="redis-cli $REDIS_CLI_TLS_CMD --cluster add-node $secondary_endpoint_with_port $mapping_primary_endpoint_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id"
    logging_mask_replicated_command="$replicated_command"
  else
    replicated_command="redis-cli $REDIS_CLI_TLS_CMD --cluster add-node $secondary_endpoint_with_port $mapping_primary_endpoint_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id -a $REDIS_DEFAULT_PASSWORD"
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
    add_node_command="redis-cli $REDIS_CLI_TLS_CMD --cluster add-node $scale_out_shard_default_primary_endpoint_with_port $exist_available_node"
    logging_mask_add_node_command="$add_node_command"
  else
    add_node_command="redis-cli $REDIS_CLI_TLS_CMD --cluster add-node $scale_out_shard_default_primary_endpoint_with_port $exist_available_node -a $REDIS_DEFAULT_PASSWORD"
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
    reshard_command="redis-cli $REDIS_CLI_TLS_CMD --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard --cluster-yes"
    logging_mask_reshard_command="$reshard_command"
  else
    reshard_command="redis-cli $REDIS_CLI_TLS_CMD --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
    logging_mask_reshard_command="${reshard_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "scale out shard reshard command: $logging_mask_reshard_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$reshard_command"
}

build_rebalance_to_zero_command() {
  local node_with_port="$1"
  local node_cluster_id="$2"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    rebalance_command="redis-cli $REDIS_CLI_TLS_CMD --cluster rebalance $node_with_port --cluster-weight $node_cluster_id=0 --cluster-yes "
    logging_mask_rebalance_command="$rebalance_command"
  else
    rebalance_command="redis-cli $REDIS_CLI_TLS_CMD --cluster rebalance $node_with_port --cluster-weight $node_cluster_id=0 --cluster-yes -a $REDIS_DEFAULT_PASSWORD"
    logging_mask_rebalance_command="${rebalance_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "set current component slot to 0 by rebalance command: $logging_mask_rebalance_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$rebalance_command"
}

build_del_node_command() {
  local available_node="$1"
  local node_to_del_cluster_id="$2"
  local do_forget_node="$3"
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    del_node_command="redis-cli $REDIS_CLI_TLS_CMD --cluster del-node $available_node $node_to_del_cluster_id -p $SERVICE_PORT"
    if [[ "$do_forget_node" == "true" ]]; then
      del_node_command="redis-cli $REDIS_CLI_TLS_CMD -p $SERVICE_PORT --cluster call $available_node cluster forget $node_to_del_cluster_id"
    fi
    logging_mask_del_node_command="$del_node_command"
  else
    del_node_command="redis-cli $REDIS_CLI_TLS_CMD --cluster del-node $available_node $node_to_del_cluster_id -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD"
    if [[ "$do_forget_node" == "true" ]]; then
      del_node_command="redis-cli $REDIS_CLI_TLS_CMD -p $SERVICE_PORT --cluster call $available_node cluster forget $node_to_del_cluster_id -a $REDIS_DEFAULT_PASSWORD"
    fi
    logging_mask_del_node_command="${del_node_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "del node command: $logging_mask_del_node_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$del_node_command"
}

build_acl_save_command() {
  local service_port="$1"
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    acl_save_command="redis-cli $REDIS_CLI_TLS_CMD -h localhost -p $service_port -a $REDIS_DEFAULT_PASSWORD acl save"
    logging_mask_acl_save_command="${acl_save_command/$REDIS_DEFAULT_PASSWORD/********}"
  else
    acl_save_command="redis-cli $REDIS_CLI_TLS_CMD -h localhost -p $service_port acl save"
    logging_mask_acl_save_command="$acl_save_command"
  fi
  echo "acl save command: $logging_mask_acl_save_command" >&2
  set_xtrace_when_ut_mode_false
  echo "$acl_save_command"
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
    echo "Failed to add the node $scale_out_shard_default_primary_endpoint_with_port to the cluster when scale_out_shard_primary_join_cluster" >&2
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
    echo "Failed to reshard the cluster when scale_out_shard_reshard" >&2
    return 1
  fi
  return 0
}

scale_in_shard_rebalance_to_zero() {
  local node_with_port="$1"
  local node_cluster_id="$2"
  rebalance_command=$(build_rebalance_to_zero_command "$node_with_port" "$node_cluster_id")
  if ! $rebalance_command; then
    echo "Failed to rebalance the cluster when scale_in_shard_rebalance_to_zero" >&2
    return 1
  fi
  return 0
}

scale_in_shard_del_node() {
  local available_node="$1"
  local node_to_del_cluster_id="$2"
  del_node_command=$(build_del_node_command "$available_node" "$node_to_del_cluster_id")
  if ! $del_node_command; then
    echo "Failed to delete the node $available_node from the cluster when scale_in_shard_del_node" >&2
    return 1
  fi
  return 0
}

secondary_member_leave_del_node() {
  local available_node="$1"
  local node_to_del_cluster_id="$2"
  local do_forget_node="$3"
  del_node_command=$(build_del_node_command "$available_node" "$node_to_del_cluster_id" "$do_forget_node")
  if ! $del_node_command; then
    echo "Failed to delete the node $available_node from the cluster when secondary_member_leave_del_node" >&2
    return 1
  fi
  return 0
}

secondary_member_leave_del_node_with_retry() {
  local available_node="$1"
  local node_to_del_cluster_id="$2"
  local do_forget_node="$3"
  check_result=$(call_func_with_retry $check_ready_times $retry_delay_second secondary_member_leave_del_node "$available_node" "$node_to_del_cluster_id" "$do_forget_node")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to remove replica when member leave after retry" >&2
    return 1
  fi
  return 0
}

execute_acl_save() {
  local service_port="$1"
  acl_save_command=$(build_acl_save_command "$service_port")
  if ! $acl_save_command; then
    echo "Failed to execute acl save command" >&2
    return 1
  fi
  return 0
}

execute_acl_save_with_retry() {
  local service_port="$1"
  check_result=$(call_func_with_retry $check_ready_times $retry_delay_second execute_acl_save $service_port)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to execute acl save command after retry" >&2
    return 1
  fi
  return 0
}

check_redis_role() {
  local host=$1
  local port=$2
  unset_xtrace_when_ut_mode_false
  if is_empty "$REDIS_DEFAULT_PASSWORD"; then
    role_info=$(redis-cli $REDIS_CLI_TLS_CMD -h $host -p $port info replication)
  else
    role_info=$(redis-cli $REDIS_CLI_TLS_CMD -h $host -p $port -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  set_xtrace_when_ut_mode_false

  if echo "$role_info" | grep -q "^role:master"; then
    echo "primary"
  elif echo "$role_info" | grep -q "^role:slave"; then
    echo "secondary"
  else
    echo "unknown"
  fi
}

redis_config_get() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4

  local output
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    output=$(redis-cli $REDIS_CLI_TLS_CMD -h "$host" -p "$port" -a "$password" $command)
  else
    output=$(redis-cli $REDIS_CLI_TLS_CMD -h "$host" -p "$port" $command)
  fi
  local status=$?
  set_xtrace_when_ut_mode_false

  if [[ $status -ne 0 ]]; then
    echo "Command failed with status $status." >&2
    return 1
  fi

  if [[ -z "$output" ]]; then
    echo "Command returned no output." >&2
    return 1
  fi

  echo "$output"
  return 0
}

build_replication_view_signature() {
  local cluster_nodes_info="$1"
  local expected_primary_id="$2"
  local current_shard_node_ids="$3"

  awk -v expected_ids="$current_shard_node_ids" -v expected_primary_id="$expected_primary_id" '
    BEGIN {
      expected_count = split(expected_ids, expected_order, ",")
      for (i = 1; i <= expected_count; i++) {
        expected[expected_order[i]] = 1
      }
    }
    {
      node_id = $1
      upstream_id = $4
      if (!(node_id in expected)) {
        if (node_id == expected_primary_id || upstream_id == expected_primary_id) {
          unexpected_node = 1
        }
        next
      }
      if (seen[node_id]++) {
        duplicate_node = 1
        next
      }

      normalized_flags = ""
      flag_count = split($3, raw_flags, ",")
      for (i = 1; i <= flag_count; i++) {
        if (raw_flags[i] == "myself") {
          continue
        }
        normalized_flags = normalized_flags (normalized_flags == "" ? "" : ",") raw_flags[i]
      }

      slots = ""
      for (i = 9; i <= NF; i++) {
        if ($i ~ /^[0-9]+(-[0-9]+)?$/) {
          slots = slots (slots == "" ? "" : ",") $i
        }
      }
      signature[node_id] = node_id "|" normalized_flags "|" upstream_id "|" slots
      if (normalized_flags ~ /(^|,)master(,|$)/ && slots != "") {
        slot_owner_count++
        slot_owner_id = node_id
      }
    }
    END {
      if (unexpected_node || duplicate_node) {
        exit 2
      }
      for (i = 1; i <= expected_count; i++) {
        if (seen[expected_order[i]] != 1) {
          exit 2
        }
      }
      if (slot_owner_count != 1 || slot_owner_id != expected_primary_id) {
        exit 3
      }
      for (i = 1; i <= expected_count; i++) {
        print signature[expected_order[i]]
      }
    }
  ' <<< "$cluster_nodes_info"
}

classify_current_node_replication_view() {
  local cluster_nodes_info="$1"
  local expected_primary_id="$2"
  local current_node_line
  local current_node_count
  local current_node_flags
  local current_node_upstream
  local current_node_slots

  current_node_count=$(awk '$3 ~ /(^|,)myself(,|$)/ { count++ } END { print count + 0 }' <<< "$cluster_nodes_info")
  if [ "$current_node_count" -ne 1 ]; then
    echo "Failed to resolve current node replication state" >&2
    return 1
  fi
  current_node_line=$(awk '$3 ~ /(^|,)myself(,|$)/ { print; exit }' <<< "$cluster_nodes_info")
  current_node_flags=$(awk '{ print $3 }' <<< "$current_node_line")
  current_node_upstream=$(awk '{ print $4 }' <<< "$current_node_line")
  current_node_slots=$(awk '{ for (i = 9; i <= NF; i++) if ($i ~ /^[0-9]+(-[0-9]+)?$/) printf "%s%s", output++ ? "," : "", $i }' <<< "$current_node_line")

  if [[ "$current_node_flags" =~ (^|,)master(,|$) ]]; then
    if [ -n "$current_node_slots" ]; then
      echo "primary_ok"
    else
      echo "repairable"
    fi
    return 0
  fi
  if [[ "$current_node_flags" =~ (^|,)slave(,|$) ]]; then
    if [ "$current_node_upstream" = "$expected_primary_id" ] && [ -z "$current_node_slots" ]; then
      echo "replica_ok"
    elif [ -z "$current_node_slots" ]; then
      echo "repairable"
    else
      echo "Failed to resolve current node replication state" >&2
      return 1
    fi
    return 0
  fi

  echo "Failed to resolve current node replication state" >&2
  return 1
}

get_consistent_current_node_replication_state() {
  local primary_endpoint="$1"
  local primary_port="$2"
  local expected_primary_id="$3"
  local current_shard_node_ids="$4"
  local local_round_one owner_round_one local_round_two owner_round_two
  local local_signature_one owner_signature_one local_signature_two owner_signature_two
  local signature_status

  if ! local_round_one=$(get_cluster_nodes_info "127.0.0.1" "$service_port"); then
    echo "Failed to read local cluster replication view" >&2
    return 1
  fi
  if ! owner_round_one=$(get_cluster_nodes_info "$primary_endpoint" "$primary_port"); then
    echo "Failed to read slot-owner cluster replication view" >&2
    return 1
  fi
  if ! local_round_two=$(get_cluster_nodes_info "127.0.0.1" "$service_port"); then
    echo "Failed to read second local cluster replication view" >&2
    return 1
  fi
  if ! owner_round_two=$(get_cluster_nodes_info "$primary_endpoint" "$primary_port"); then
    echo "Failed to read second slot-owner cluster replication view" >&2
    return 1
  fi

  if local_signature_one=$(build_replication_view_signature "$local_round_one" "$expected_primary_id" "$current_shard_node_ids"); then
    :
  else
    signature_status=$?
    if [ "$signature_status" -eq 3 ]; then
      echo "Expected exactly one slot-owning primary" >&2
    else
      echo "Cluster replication views disagree" >&2
    fi
    return 1
  fi
  if owner_signature_one=$(build_replication_view_signature "$owner_round_one" "$expected_primary_id" "$current_shard_node_ids"); then
    :
  else
    signature_status=$?
    if [ "$signature_status" -eq 3 ]; then
      echo "Expected exactly one slot-owning primary" >&2
    else
      echo "Cluster replication views disagree" >&2
    fi
    return 1
  fi
  if [ "$local_signature_one" != "$owner_signature_one" ]; then
    echo "Cluster replication views disagree" >&2
    return 1
  fi

  if ! local_signature_two=$(build_replication_view_signature "$local_round_two" "$expected_primary_id" "$current_shard_node_ids"); then
    echo "Cluster replication view changed before mutation" >&2
    return 1
  fi
  if ! owner_signature_two=$(build_replication_view_signature "$owner_round_two" "$expected_primary_id" "$current_shard_node_ids"); then
    echo "Cluster replication view changed before mutation" >&2
    return 1
  fi
  if [ "$local_signature_two" != "$owner_signature_two" ]; then
    echo "Cluster replication views disagree" >&2
    return 1
  fi
  if [ "$local_signature_one" != "$local_signature_two" ]; then
    echo "Cluster replication view changed before mutation" >&2
    return 1
  fi

  classify_current_node_replication_view "$local_round_two" "$expected_primary_id"
}

get_current_shard_node_ids() {
  local primary_endpoint="$1"
  local primary_port="$2"
  local expected_primary_id="$3"
  local local_view owner_view current_node_id current_shard_node_ids

  if ! local_view=$(get_cluster_nodes_info "127.0.0.1" "$service_port"); then
    echo "Failed to read local cluster view for current shard node IDs" >&2
    return 1
  fi
  if ! owner_view=$(get_cluster_nodes_info "$primary_endpoint" "$primary_port"); then
    echo "Failed to read slot-owner cluster view for current shard node IDs" >&2
    return 1
  fi
  current_node_id=$(awk '$3 ~ /(^|,)myself(,|$)/ { print $1; exit }' <<< "$local_view")
  if [ -z "$current_node_id" ]; then
    echo "Failed to resolve current node ID" >&2
    return 1
  fi
  current_shard_node_ids=$(awk -v primary_id="$expected_primary_id" -v current_id="$current_node_id" '
    $1 == primary_id || $4 == primary_id || $1 == current_id { ids[$1] = 1 }
    END {
      ids[primary_id] = 1
      ids[current_id] = 1
      print primary_id
      for (id in ids) if (id != primary_id && id != current_id) print id
      if (current_id != primary_id) print current_id
    }
  ' <<< "$owner_view" | paste -sd, -)
  if [ -z "$current_shard_node_ids" ] || [[ "$current_shard_node_ids" != *","* ]]; then
    echo "Failed to resolve current shard node-ID set" >&2
    return 1
  fi
  echo "$current_shard_node_ids"
}

repair_current_node_replication() {
  local expected_primary_id="$1"
  local output
  local status
  local logging_command="redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $service_port"

  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    logging_command="$logging_command -a ******** CLUSTER REPLICATE $expected_primary_id"
    echo "repair current node replication command: $logging_command" >&2
    if output=$(redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p "$service_port" -a "$REDIS_DEFAULT_PASSWORD" CLUSTER REPLICATE "$expected_primary_id"); then
      status=0
    else
      status=$?
    fi
  else
    logging_command="$logging_command CLUSTER REPLICATE $expected_primary_id"
    echo "repair current node replication command: $logging_command" >&2
    if output=$(redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p "$service_port" CLUSTER REPLICATE "$expected_primary_id"); then
      status=0
    else
      status=$?
    fi
  fi
  set_xtrace_when_ut_mode_false
  if [ "$status" -ne 0 ]; then
    echo "Failed to execute current node replication repair" >&2
    return 1
  fi
  echo "$output"
}

verify_current_node_replication() {
  local primary_endpoint="$1"
  local primary_port="$2"
  local expected_primary_id="$3"
  local current_shard_node_ids="$4"
  local max_attempts="${check_ready_times:-2}"
  local attempt=1
  local state
  local verification_output

  if [ "$max_attempts" -gt 3 ]; then
    max_attempts=3
  fi
  while [ "$attempt" -le "$max_attempts" ]; do
    if verification_output=$(get_consistent_current_node_replication_state "$primary_endpoint" "$primary_port" "$expected_primary_id" "$current_shard_node_ids" 2>&1); then
      state="$verification_output"
      if [ "$state" = "replica_ok" ]; then
        return 0
      fi
    else
      case "$verification_output" in
        *"views disagree"*) echo "Post-repair cluster replication views disagree" >&2 ;;
        *"view changed"*) echo "Post-repair cluster replication view changed" >&2 ;;
        *) echo "Post-repair cluster replication verification failed: $verification_output" >&2 ;;
      esac
      return 1
    fi
    attempt=$((attempt + 1))
    if [ "$attempt" -le "$max_attempts" ]; then
      sleep_when_ut_mode_false "$retry_delay_second"
    fi
  done

  echo "Replication repair verification timeout" >&2
  return 1
}

ensure_current_node_replication() {
  if [ "$#" -ne 4 ]; then
    echo "ensure_current_node_replication requires primary endpoint, port, ID, and shard node IDs" >&2
    return 1
  fi

  local primary_endpoint="$1"
  local primary_port="$2"
  local expected_primary_id="$3"
  local current_shard_node_ids="$4"
  local state
  if ! state=$(get_consistent_current_node_replication_state "$primary_endpoint" "$primary_port" "$expected_primary_id" "$current_shard_node_ids"); then
    echo "Failed to get consistent current node replication state" >&2
    return 1
  fi
  case "$state" in
    replica_ok)
      echo "Current node already replicates expected primary $expected_primary_id"
      return 0
      ;;
    primary_ok)
      echo "Current node is the legal slot-owning primary $expected_primary_id"
      return 0
      ;;
    repairable)
      if ! repair_current_node_replication "$expected_primary_id"; then
        echo "Failed to repair current node replication" >&2
        return 1
      fi
      if ! verify_current_node_replication "$primary_endpoint" "$primary_port" "$expected_primary_id" "$current_shard_node_ids"; then
        echo "Current node replication did not converge to expected primary $expected_primary_id" >&2
        return 1
      fi
      return 0
      ;;
    *)
      echo "Refusing to repair current node from state $state" >&2
      return 1
      ;;
  esac
}

forget_fail_node_when_cluster_is_ok() {
  local host=$1
  local port=$2
  unset_xtrace_when_ut_mode_false
  cluster_info=$(get_cluster_info_with_retry "$host" "$port")
  cluster_state=$(echo "$cluster_info" | awk -F: '/cluster_state/{print $2}' | tr -d '[:space:]')
  if [[ "$cluster_state" != "ok" ]]; then
    echo "Cluster state is not ok, skip forget fail node"
    set_xtrace_when_ut_mode_false
    return 0
  fi
  cluster_nodes_info=$(get_cluster_nodes_info "$host" "$port")
  while read -r line; do
    node_id=$(echo "$line" | awk '{print $1}')
    node_role=$(echo "$line" | awk '{print $3}')
    if [[ "$node_role" == "fail" ]]; then
      if [ -z ${REDIS_DEFAULT_PASSWORD} ]; then
        redis-cli -h $host -p $port --cluster call $host:$port cluster forget ${node_id}
      else
        redis-cli -h $host -p $port --cluster call $host:$port cluster forget ${node_id} -a ${REDIS_DEFAULT_PASSWORD}
      fi
    fi
  done <<< "$cluster_nodes_info"
  set_xtrace_when_ut_mode_false
}
