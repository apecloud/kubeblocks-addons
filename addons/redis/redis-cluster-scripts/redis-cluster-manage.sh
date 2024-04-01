#!/bin/bash
set -ex

# initialize the other component and pods info
init_other_component_pods_info() {
  local component="$1"
  local all_pod_ip_list="$2"
  local all_pod_name_list="$3"
  local all_component_list="$4"
  other_components=()
  other_component_pod_ips=()
  other_component_pod_names=()
  other_component_nodes=()
  echo "init other components and pods info, current component: $component"
  # filter out the components of the given component
  IFS=',' read -ra components <<< "$all_component_list"
  for comp in "${components[@]}"; do
    if [ "$comp" = "$component" ]; then
      echo "skip the component $comp as it is the current component"
      continue
    fi
    other_components+=("$comp")
  done

  # filter out the pods of the given component
  IFS=',' read -ra pod_ips <<< "$all_pod_ip_list"
  IFS=',' read -ra pod_names <<< "$all_pod_name_list"
  for index in "${!pod_ips[@]}"; do
    if echo "${pod_names[$index]}" | grep "$component-"; then
      echo "skip the pod ${pod_names[$index]} as it belongs the component $component"
      continue
    fi
    other_component_pod_ips+=("${pod_ips[$index]}")
    other_component_pod_names+=("${pod_names[$index]}")

    pod_name_prefix=$(extract_pod_name_prefix "${pod_names[$index]}")
    pod_fqdn="${pod_names[$index]}.$pod_name_prefix-headless"
    other_component_nodes+=("$pod_fqdn:$SERVICE_PORT")
  done

  echo "other_components: ${other_components[*]}"
  echo "other_component_pod_ips: ${other_component_pod_ips[*]}"
  echo "other_component_pod_names: ${other_component_pod_names[*]}"
  echo "other_component_nodes: ${other_component_nodes[*]}"
}

find_exist_available_node() {
  for node in "${other_component_nodes[@]}"; do
    if redis_cluster_check "$node"; then
      echo "$node"
      return
    fi
  done
  echo ""
}

# usage: parse_host_ip_from_built_in_envs <pod_name>
parse_host_ip_from_built_in_envs() {
  local given_pod_name="$1"
  local all_pod_name_list="$2"
  local all_pod_host_ip_list="$3"

  if [ -z "$all_pod_name_list" ] || [ -z "$all_pod_host_ip_list" ]; then
    echo "Error: Required environment variables all_pod_name_lis or all_pod_host_ip_list are not set."
    exit 1
  fi

  old_ifs="$IFS"
  IFS=','
  set -f
  pod_name_list="$all_pod_name_list"
  pod_ip_list="$all_pod_host_ip_list"
  set +f
  IFS="$old_ifs"

  while [ -n "$pod_name_list" ]; do
    pod_name="${pod_name_list%%,*}"
    host_ip="${pod_ip_list%%,*}"

    if [ "$pod_name" = "$given_pod_name" ]; then
      echo "$host_ip"
      return 0
    fi

    if [ "$pod_name_list" = "$pod_name" ]; then
      pod_name_list=''
      pod_ip_list=''
    else
      pod_name_list="${pod_name_list#*,}"
      pod_ip_list="${pod_ip_list#*,}"
    fi
  done

  echo "parse_host_ip_from_built_in_envs the given pod name $given_pod_name not found."
  exit 1
}

# usage: wait_random_time <max_time> <min_time>
wait_random_second() {
  local max_time="$1"
  local min_time="$2"
  local random_time=$((RANDOM % (max_time - min_time + 1) + min_time))
  echo "Sleeping for $random_time seconds"
  sleep "$random_time"
}

redis_cluster_check() {
  # check redis cluster all slots are covered
  local cluster_node="$1"
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    check=$(redis-cli --cluster check "$cluster_node" -p "$SERVICE_PORT")
  else
    check=$(redis-cli --cluster check "$cluster_node" -p "$SERVICE_PORT" -a "$REDIS_DEFAULT_PASSWORD" )
  fi
  if [[ $check =~ "All 16384 slots covered" ]]; then
    true
  else
    false
  fi
}

wait_for_dns_lookup() {
    local hostname="${1:?hostname is missing}"
    local retries="${2:-5}"
    local seconds="${3:-1}"
    check_host() {
        if [[ $(dns_lookup "$hostname") == "" ]]; then
            false
        else
            true
        fi
    }
    # Wait for the host to be ready
    retry_while "check_host ${hostname}" "$retries" "$seconds"
    dns_lookup "$hostname"
}

extract_ordinal_from_pod_name() {
  local pod_name="$1"
  local ordinal="${pod_name##*-}"
  echo "$ordinal"
}

extract_pod_name_prefix() {
  local pod_name="$1"
  # shellcheck disable=SC2001
  prefix=$(echo "$pod_name" | sed 's/-[0-9]\+$//')
  echo "$prefix"
}

# pod_fqdn example: redis-sharding-shard-gl9-1.redis-sharding-shard-gl9-headless
extract_pod_name_prefix_from_pod_fqdn() {
  local pod_fqdn="$1"
  regex="^(.*)-[0-9]+\..*$"
  if [[ $pod_fqdn =~ $regex ]]; then
    result="${BASH_REMATCH[1]}"
    echo "$result"
  else
    echo ""
  fi
}

is_redis_cluster_initialized() {
  if [ -z "$KB_CLUSTER_POD_IP_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_IP_LIST is not set."
    exit 1
  fi
  local initialized="false"
  for pod_ip in $(echo "$KB_CLUSTER_POD_IP_LIST" | tr ',' ' '); do
    cluster_info=$(redis-cli -h "$pod_ip" -a "$REDIS_DEFAULT_PASSWORD" cluster info)
    echo "cluster_info $cluster_info"
    cluster_state=$(echo "$cluster_info" | grep -oP '(?<=cluster_state:)[^\s]+')
    if [ -z "$cluster_state" ] || [ "$cluster_state" == "ok" ]; then
      echo "Redis Cluster already initialized"
      initialized="true"
      break
    fi
  done
  [ "$initialized" = "true" ]
}

# get the current component primary node and other nodes for scale in
get_current_comp_nodes_for_scale_in() {
  local cluster_node="$1"
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$SERVICE_PORT" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$SERVICE_PORT" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi

  current_comp_primary_node=()
  current_comp_other_nodes=()

  # the output of line is like:
  # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # TODO: when support nodePort or LoadBalancer, the output of line will not contain the $KB_CLUSTER_COMP_NAME
  while read -r line; do
    node_fqdn=$(echo "$line" | awk '{print $2}' | awk -F ',' '{print $2}')
    node_role=$(echo "$line" | awk '{print $3}')

    if [[ "$node_fqdn" =~ "$KB_CLUSTER_COMP_NAME"* ]]; then
      if [[ "$node_role" =~ "master" ]]; then
        current_comp_primary_node+=("$node_fqdn:$SERVICE_PORT")
      else
        current_comp_other_nodes+=("$node_fqdn:$SERVICE_PORT")
      fi
    fi
  done <<< "$cluster_nodes_info"

  echo "current_comp_primary_node: ${current_comp_primary_node[*]}"
  echo "current_comp_other_nodes: ${current_comp_other_nodes[*]}"
}

# get the current component default primary node which ordinal is 0 to join the cluster when scaling out
init_current_comp_default_nodes_for_scale_out() {
    if [ -z "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" ]; then
      echo "Error: Required environment variable KB_CLUSTER_COMPONENT_POD_NAME_LIST is not set."
      exit 1
    fi
    current_comp_default_primary_node=()
    current_comp_default_other_nodes=()
    local port=$SERVICE_PORT
    for pod_name in $(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' ' '); do
      pod_name_ordinal=$(extract_ordinal_from_pod_name "$pod_name")
      pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
      local pod_fqdn="$pod_name.$pod_name_prefix-headless"
      if [ "$pod_name_ordinal" -eq 0 ]; then
        current_comp_default_primary_node+=(" $pod_fqdn:$port")
      else
        current_comp_default_other_nodes+=(" $pod_fqdn:$port")
      fi
    done
    echo "current_comp_default_primary_node: ${current_comp_default_primary_node[*]}"
    echo "current_comp_default_other_nodes: ${current_comp_default_other_nodes[*]}"
}

gen_initialize_redis_cluster_primary_node() {
  if [ -z "$KB_CLUSTER_POD_NAME_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST is not set."
    exit 1
  fi
  local cluster_nodes=()
  local port=$SERVICE_PORT
  for pod_name in $(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' ' '); do
    pod_name_ordinal=$(extract_ordinal_from_pod_name "$pod_name")
    if [ "$pod_name_ordinal" -ne 0 ]; then
      continue
    fi
    pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
    local pod_fqdn="$pod_name.$pod_name_prefix-headless"
    cluster_nodes+=(" $pod_fqdn:$port")
  done
  echo "${cluster_nodes[*]}"
}

gen_initialize_redis_cluster_secondary_nodes() {
  if [ -z "$KB_CLUSTER_POD_NAME_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST is not set."
    exit 1
  fi
  local cluster_nodes=()
  local port=$SERVICE_PORT
  for pod_name in $(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' ' '); do
    pod_name_ordinal=$(extract_ordinal_from_pod_name "$pod_name")
    if [ "$pod_name_ordinal" -eq 0 ]; then
      continue
    fi
    pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
    local pod_fqdn="$pod_name.$pod_name_prefix-headless"
    cluster_nodes+=(" $pod_fqdn:$port")
  done
  echo "${cluster_nodes[*]}"
}

get_cluster_id() {
  local cluster_node="$1"
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$SERVICE_PORT" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$SERVICE_PORT" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
  echo "$cluster_id"
}

initialize_redis_cluster() {
  # initialize all the primary nodes
  primary_nodes=$(gen_initialize_redis_cluster_primary_node)
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      initialize_command="redis-cli --cluster create $primary_nodes --cluster-yes"
  else
      initialize_command="redis-cli --cluster create $primary_nodes -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
  fi
  if ! $initialize_command
  then
      echo "Failed to create Redis Cluster"
      exit 1
  fi

  # get the first primary node to check the cluster
  first_primary_node=$(echo "$primary_nodes" | awk '{print $1}')
  if redis_cluster_check "$first_primary_node"; then
      echo "Cluster correctly created"
  else
      echo "Failed to create Redis Cluster"
      exit 1
  fi
  # initialize all the secondary nodes
  secondary_nodes=$(gen_initialize_redis_cluster_secondary_nodes)
  echo "secondary_nodes: $secondary_nodes"
  for secondary_node in $secondary_nodes; do
      secondary_pod_name_prefix=$(extract_pod_name_prefix_from_pod_fqdn "$secondary_node")
      mapping_primary_fqdn="$secondary_pod_name_prefix-0.$secondary_pod_name_prefix-headless"
      mapping_primary_fqdn_with_port="$mapping_primary_fqdn:$SERVICE_PORT"
      mapping_primary_cluster_id=$(get_cluster_id "$mapping_primary_fqdn")
      echo "mapping_primary_fqdn: $mapping_primary_fqdn, mapping_primary_fqdn_with_port: $mapping_primary_fqdn_with_port, mapping_primary_cluster_id: $mapping_primary_cluster_id"
      if [ -z "$mapping_primary_cluster_id" ]; then
          echo "Failed to get the cluster id from cluster nodes of the mapping primary node: $mapping_primary_fqdn"
          exit 1
      fi
      if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
          replicated_command="redis-cli --cluster add-node $secondary_node $mapping_primary_fqdn_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id"
      else
          replicated_command="redis-cli --cluster add-node $secondary_node $mapping_primary_fqdn_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id -a $REDIS_DEFAULT_PASSWORD"
      fi
      echo "replicated_command: $replicated_command"
      if ! $replicated_command
      then
          echo "Failed to add the node $secondary_node to the cluster in initialize_redis_cluster"
          exit 1
      fi
  done
}

scale_out_redis_cluster_shard() {
  init_other_component_pods_info "$KB_CLUSTER_COMP_NAME" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_POD_NAME_LIST"
  init_current_comp_default_nodes_for_scale_out

  # check the current component shard whether is already scaled out
  primary_node_with_port=$(echo "${current_comp_default_primary_node[*]}" | awk '{print $1}')
  primary_node_fqdn=$(echo "$primary_node_with_port" | awk -F ':' '{print $1}')
  mapping_primary_cluster_id=$(get_cluster_id "$primary_node_fqdn")
  if redis_cluster_check "$primary_node_with_port"; then
    echo "The current component shard is already scaled out, no need to scale out again."
    exit 0
  fi

  # find the exist available node which is not in the current component
  available_node=$(find_exist_available_node)
  if [ -z "$available_node" ]; then
    echo "No exist available node found or cluster status is not ok"
    exit 1
  fi

  # add the default primary node for the current shard
  for current_comp_default_primary_node in $current_comp_default_primary_node; do
      if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
        echo "redis-cli --cluster add-node $current_comp_default_primary_node $available_node"
        redis-cli --cluster add-node "$current_comp_default_primary_node" "$available_node"
      else
        echo "redis-cli --cluster add-node $current_comp_default_primary_node $available_node -a $REDIS_DEFAULT_PASSWORD"
        redis-cli --cluster add-node "$current_comp_default_primary_node" "$available_node" -a "$REDIS_DEFAULT_PASSWORD"
      fi
  done

  # waiting for all nodes sync the information
  wait_random_second 10 5

  # add the default other secondary nodes for the current shard
  for current_comp_default_other_node in ${current_comp_default_other_nodes[*]}; do
      # gei mapping master id
      echo "primary_node_with_port: $primary_node_with_port, primary_node_fqdn: $primary_node_fqdn, mapping_primary_cluster_id: $mapping_primary_cluster_id"
      if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
          replicated_command="redis-cli --cluster add-node $current_comp_default_other_node $primary_node_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id"
      else
          replicated_command="redis-cli --cluster add-node $current_comp_default_other_node $primary_node_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id -a $REDIS_DEFAULT_PASSWORD"
      fi
      echo "replicated_command: $replicated_command"
      # execute the replicated command
      if ! $replicated_command
      then
          echo "Failed to add the node $current_comp_default_other_node to the cluster"
          exit 1
      fi
  done

  # do the reshard
  # TODO: optimize the number of reshard slots according to the cluster status
  total_slots=16384
  current_comp_pod_count=$(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' '\n' | grep -c "^$KB_CLUSTER_COMP_NAME-")
  all_comp_pod_count=$(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' '\n' | grep -c ".*")
  shard_count=$((all_comp_pod_count / current_comp_pod_count))
  slots_per_shard=$((total_slots / shard_count))
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      reshard_command="redis-cli --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard --cluster-yes"
  else
      reshard_command="redis-cli --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
  fi
  echo "reshard_command: $reshard_command"
  if ! $reshard_command
  then
      echo "Failed to reshard the cluster"
      exit 1
  fi

  # rebalance the cluster
  #  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
  #      rebalance_command="redis-cli --cluster rebalance $primary_node_with_port --cluster-timeout 3000 --cluster-simulate"
  #  else
  #      rebalance_command="redis-cli --cluster rebalance $primary_node_with_port --cluster-timeout 3000 --cluster-simulate -a $REDIS_DEFAULT_PASSWORD"
  #  fi
  #  echo "rebalance_command: $rebalance_command"
  #  if ! $rebalance_command
  #  then
  #      echo "Failed to rebalance the cluster"
  #      exit 1
  #  fi
}

scale_in_redis_cluster_shard() {
  init_other_component_pods_info "$KB_CLUSTER_COMP_NAME" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_POD_NAME_LIST"
  available_node=$(find_exist_available_node)
  available_node_fqdn=$(echo "$available_node" | awk -F ':' '{print $1}')
  get_current_comp_nodes_for_scale_in "$available_node_fqdn"

  # Check if the number of shards in the cluster is less than 3 after scaling down.
  current_comp_pod_count=0
  for pod_name in $(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' ' '); do
    if [[ "$pod_name" == "$KB_CLUSTER_COMP_NAME"* ]]; then
      current_comp_pod_count=$((current_comp_pod_count + 1))
    fi
  done
  shard_count=$((${#other_component_nodes[@]} / current_comp_pod_count))
  if [ $shard_count -lt 3 ]; then
    echo "The number of shards in the cluster is less than 3 after scaling in, skip scaling in"
    exit 0
  fi

  # set the current component slot to 0 by rebalance command
  for primary_node in "${current_comp_primary_node[@]}"; do
    primary_node_fqdn=$(echo "$primary_node" | awk -F ':' '{print $1}')
    primary_node_cluster_id=$(get_cluster_id "$primary_node_fqdn")

    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      rebalance_command="redis-cli --cluster rebalance $primary_node --cluster-weight $primary_node_cluster_id=0 --cluster-yes "
    else
      rebalance_command="redis-cli --cluster rebalance $primary_node --cluster-weight $primary_node_cluster_id=0 --cluster-yes -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "set current component slot to 0 by rebalance_command: $rebalance_command"
    if ! $rebalance_command
    then
      echo "Failed to rebalance the cluster for the current component when scaling in"
      exit 1
    fi
  done

  wait_random_second 10 5

  # delete the current component nodes from the cluster
  for node_to_del in "${current_comp_primary_node[@]}" "${current_comp_other_nodes[@]}"; do
    node_to_del_fqdn=$(echo "$node_to_del" | awk -F ':' '{print $1}')
    node_to_del_cluster_id=$(get_cluster_id "$node_to_del_fqdn")
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      del_node_command="redis-cli --cluster del-node $available_node $node_to_del_cluster_id -p $SERVICE_PORT"
    else
      del_node_command="redis-cli --cluster del-node $available_node $node_to_del_cluster_id -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "del_node_command: $del_node_command"
    if ! $del_node_command
    then
      echo "Failed to delete the node $node_to_del from the cluster when scaling in"
      exit 1
    fi
  done
}

initialize_or_scale_out_redis_cluster() {
    # TODO: remove random sleep, it's a workaround for the multi components initialization parallelism issue
    wait_random_second 10 1

    # if the cluster is not initialized, initialize it
    if ! is_redis_cluster_initialized; then
        echo "Redis Cluster not initialized, initializing..."
        initialize_redis_cluster
    else
        echo "Redis Cluster already initialized, scaling out the shard..."
        scale_out_redis_cluster_shard
    fi
}

# main
if [ $# -eq 1 ]; then
  case $1 in
  --help)
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --help                show help information"
    echo "  --post-provision      initialize or scale out Redis Cluster Shard"
    echo "  --pre-terminate       stop or scale in Redis Cluster Shard"
    exit 0
    ;;
  --post-provision)
    initialize_or_scale_out_redis_cluster
    exit 0
    ;;
  --pre-terminate)
    scale_in_redis_cluster_shard
    exit 0
    ;;
  *)
    echo "Error: invalid option '$1'"
    exit 1
    ;;
  esac
fi
