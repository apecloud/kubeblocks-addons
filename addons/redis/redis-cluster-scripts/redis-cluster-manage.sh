#!/bin/bash
set -ex

# declare the global variables for initialize redis cluster
declare -gA initialize_redis_cluster_primary_nodes
declare -gA initialize_redis_cluster_secondary_nodes
declare -gA initialize_pod_name_to_advertise_host_port_map

# declare the global variables for scale out redis cluster shard
declare -gA scale_out_shard_default_primary_node
declare -gA scale_out_shard_default_other_nodes

# initialize the other component and pods info
init_other_components_and_pods_info() {
  local component="$1"
  local all_pod_ip_list="$2"
  local all_pod_name_list="$3"
  local all_component_list="$4"
  local all_deleting_component_list="$5"
  local all_undeleted_component_list="$6"

  other_components=()
  other_deleting_components=()
  other_undeleted_components=()
  other_undeleted_component_pod_ips=()
  other_undeleted_component_pod_names=()
  other_undeleted_component_nodes=()
  echo "init other components and pods info, current component: $component"
  # filter out the components of the given component
  IFS=',' read -ra components <<< "$all_component_list"
  IFS=',' read -ra deleting_components <<< "$all_deleting_component_list"
  IFS=',' read -ra undeleted_components <<< "$all_undeleted_component_list"
  for comp in "${components[@]}"; do
    if [ "$comp" = "$component" ]; then
      echo "skip the component $comp as it is the current component"
      continue
    fi
    other_components+=("$comp")
  done
  for comp in "${deleting_components[@]}"; do
    if [ "$comp" = "$component" ]; then
      echo "skip the component $comp as it is the current component"
      continue
    fi
    other_deleting_components+=("$comp")
  done
  for comp in "${undeleted_components[@]}"; do
    if [ "$comp" = "$component" ]; then
      echo "skip the component $comp as it is the current component"
      continue
    fi
    other_undeleted_components+=("$comp")
  done

  # filter out the pods of the given component
  IFS=',' read -ra pod_ips <<< "$all_pod_ip_list"
  IFS=',' read -ra pod_names <<< "$all_pod_name_list"
  for index in "${!pod_ips[@]}"; do
    if echo "${pod_names[$index]}" | grep "$component-"; then
      echo "skip the pod ${pod_names[$index]} as it belongs the component $component"
      continue
    fi

    # skip the pod belongs to the deleting component
    pod_name_prefix=$(extract_pod_name_prefix "${pod_names[$index]}")
    if echo "${deleting_components[@]}" | grep -q "$pod_name_prefix"; then
      echo "skip the pod ${pod_names[$index]} as it belongs to the deleting component $pod_name_prefix"
      continue
    fi

    other_undeleted_component_pod_ips+=("${pod_ips[$index]}")
    other_undeleted_component_pod_names+=("${pod_names[$index]}")

    pod_name_prefix=$(extract_pod_name_prefix "${pod_names[$index]}")
    pod_fqdn="${pod_names[$index]}.$pod_name_prefix-headless"
    other_undeleted_component_nodes+=("$pod_fqdn:$SERVICE_PORT")
  done

  echo "other_components: ${other_components[*]}"
  echo "other_deleting_components: ${other_deleting_components[*]}"
  echo "other_undeleted_components: ${other_undeleted_components[*]}"
  echo "other_undeleted_component_pod_ips: ${other_undeleted_component_pod_ips[*]}"
  echo "other_undeleted_component_pod_names: ${other_undeleted_component_pod_names[*]}"
  echo "other_undeleted_component_nodes: ${other_undeleted_component_nodes[*]}"
}

find_exist_available_node() {
  for node in "${other_undeleted_component_nodes[@]}"; do
    if redis_cluster_check "$node"; then
      # the $node is the headless address by default, we should get the real node address from cluster nodes
      node_ip=$(echo "$node" | cut -d':' -f1)
      node_port=$(echo "$node" | cut -d':' -f2)
      set +x
      if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
        cluster_nodes_info=$(redis-cli -h "$node_ip" -p "$node_port" cluster nodes)
      else
        cluster_nodes_info=$(redis-cli -h "$node_ip" -p "$node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes )
      fi
      set -x
      # grep my self node and return the nodeIp:port(it may be the announceIp and announcePort, for example when cluster enable NodePort/LoadBalancer service)
      available_node_with_port=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $2}' | cut -d'@' -f1)
      echo "$available_node_with_port"
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
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    check=$(redis-cli --cluster check "$cluster_node" -p "$SERVICE_PORT")
  else
    check=$(redis-cli --cluster check "$cluster_node" -p "$SERVICE_PORT" -a "$REDIS_DEFAULT_PASSWORD" )
  fi
  set -x
  if [[ $check =~ "All 16384 slots covered" ]]; then
    true
  else
    false
  fi
}

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
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

get_cluster_id() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$cluster_node_port" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$cluster_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x
  cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
  echo "$cluster_id"
}

is_redis_cluster_initialized() {
  if [ -z "$KB_CLUSTER_POD_IP_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_IP_LIST is not set."
    exit 1
  fi
  local initialized="false"
  for pod_ip in $(echo "$KB_CLUSTER_POD_IP_LIST" | tr ',' ' '); do
    set +x
    cluster_info=$(redis-cli -h "$pod_ip" -a "$REDIS_DEFAULT_PASSWORD" cluster info)
    set -x
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
  local cluster_node_port="$2"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$cluster_node_port" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$cluster_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x

  current_comp_primary_node=()
  current_comp_other_nodes=()

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -eq 1 ]; then
    echo "Cluster nodes info contains only one line, returning..."
    return
  fi

  # if the $REDIS_CLUSTER_ADVERTISED_PORT is set, parse the advertised ports
  # the value format of $REDIS_CLUSTER_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  declare -A advertised_ports
  local using_advertised_ports=false
  if [ -n "$REDIS_CLUSTER_ADVERTISED_PORT" ]; then
    using_advertised_ports=true
    IFS=',' read -ra ADDR <<< "$REDIS_CLUSTER_ADVERTISED_PORT"
    for i in "${ADDR[@]}"; do
      port=$(echo $i | cut -d':' -f2)
      advertised_ports[$port]=1
    done
  fi

  # the output of line is like:
  # 1. using the pod fqdn as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # 2. using the nodeport or lb ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:31000@31888,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc master master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  while read -r line; do
    # 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc
    node_ip_port_fields=$(echo "$line" | awk '{print $2}')
    # ip:port without bus port
    node_ip_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}')
    node_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f2)
    # redis-shard-sxj-0.redis-shard-sxj-headless.default.svc
    node_fqdn=$(echo "$line" | awk '{print $2}' | awk -F ',' '{print $2}')
    node_role=$(echo "$line" | awk '{print $3}')
    if $using_advertised_ports; then
      if [[ ${advertised_ports[$node_port]+_} ]]; then
        if [[ "$node_role" =~ "master" ]]; then
          current_comp_primary_node+=("$node_ip_port")
        else
          current_comp_other_nodes+=("$node_ip_port")
        fi
      fi
    else
      if [[ "$node_fqdn" =~ "$KB_CLUSTER_COMP_NAME"* ]]; then
        if [[ "$node_role" =~ "master" ]]; then
          current_comp_primary_node+=("$node_fqdn:$SERVICE_PORT")
        else
          current_comp_other_nodes+=("$node_fqdn:$SERVICE_PORT")
        fi
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
  local pod_host_ip
  for pod_name in $(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' ' '); do
    pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
    ## if the REDIS_CLUSTER_ADVERTISED_PORT is set, use the advertised port
    ## the value format of REDIS_CLUSTER_ADVERTISED_PORT is "pod1Svc:nodeport1,pod2Svc:nodeport2,..."
    if [ -n "$REDIS_CLUSTER_ADVERTISED_PORT" ]; then
      old_ifs="$IFS"
      IFS=','
      set -f
      read -ra advertised_infos <<< "$REDIS_CLUSTER_ADVERTISED_PORT"
      set +f
      IFS="$old_ifs"
      found_advertised_port=false
      for advertised_info in "${advertised_infos[@]}"; do
        advertised_svc=$(echo "$advertised_info" | cut -d':' -f1)
        advertised_port=$(echo "$advertised_info" | cut -d':' -f2)
        advertised_svc_ordinal=$(extract_ordinal_from_object_name "$advertised_svc")
        if [ "$pod_name_ordinal" == "$advertised_svc_ordinal" ]; then
          pod_host_ip=$(parse_host_ip_from_built_in_envs "$pod_name" "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST")
          if [ -z "$pod_host_ip" ]; then
            echo "Failed to get the host ip of the pod $pod_name"
            exit 1
          fi
          if [ "$pod_name_ordinal" -eq 0 ]; then
            scale_out_shard_default_primary_node["$pod_name"]="$pod_host_ip:$advertised_port"
          else
            scale_out_shard_default_other_nodes["$pod_name"]="$pod_host_ip:$advertised_port"
          fi
          found_advertised_port=true
          break
        fi
      done
      if [ "$found_advertised_port" = false ]; then
        echo "Advertised port not found for pod $pod_name"
        exit 1
      fi
    else
      local port=$SERVICE_PORT
      pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
      local pod_fqdn="$pod_name.$pod_name_prefix-headless"
      if [ "$pod_name_ordinal" -eq 0 ]; then
        scale_out_shard_default_primary_node["$pod_name"]="$pod_fqdn:$port"
      else
        scale_out_shard_default_other_nodes["$pod_name"]="$pod_fqdn:$port"
      fi
    fi
  done
}

gen_initialize_redis_cluster_node() {
  local is_primary=$1
  if [ -z "$KB_CLUSTER_POD_NAME_LIST" ]; then
    echo "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST is not set."
    exit 1
  fi
  local shard_name
  local shard_advertised_infos
  local shard_advertised_svc
  local shard_advertised_port
  local shard_advertised_svc_ordinal
  local pod_host_ip
  for pod_name in $(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' ' '); do
    pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
    if [ "$is_primary" = true ] && [ "$pod_name_ordinal" -ne 0 ]; then
      continue
    elif [ "$is_primary" = false ] && [ "$pod_name_ordinal" -eq 0 ]; then
      continue
    fi
    ## if the REDIS_CLUSTER_ALL_SHARDS_ADVERTISED_PORT is set, use the advertised port
    ## the value format of REDIS_CLUSTER_ALL_SHARDS_ADVERTISED_PORT is "shard-98x@redis-shard-98x-redis-advertised-0:32024,redis-shard-98x-redis-advertised-1:31318.shard-cq7@redis-shard-cq7-redis-advertised-0:31828,redis-shard-cq7-redis-advertised-1:32000"
    if [ -n "$REDIS_CLUSTER_ALL_SHARDS_ADVERTISED_PORT" ]; then
      old_ifs="$IFS"
      IFS='.'
      set -f
      read -ra shards <<< "$REDIS_CLUSTER_ALL_SHARDS_ADVERTISED_PORT"
      set +f
      IFS="$old_ifs"
      for shard in "${shards[@]}"; do
        shard_name=$(echo "$shard" | cut -d'@' -f1)
        ## if pod_name is not belong to the current shard, skip it
        if ! echo "$pod_name" | grep -q "$shard_name"; then
          continue
        fi
        # shard_advertised_infos like "redis-shard-98x-redis-advertised-0:32024,redis-shard-98x-redis-advertised-1:31318"
        old_ifs="$IFS"
        IFS=','
        set -f
        read -ra shard_advertised_infos <<< "$(echo "$shard" | cut -d'@' -f2)"
        set +f
        IFS="$old_ifs"
        for shard_advertised_info in "${shard_advertised_infos[@]}"; do
          shard_advertised_svc=$(echo "$shard_advertised_info" | cut -d':' -f1)
          shard_advertised_port=$(echo "$shard_advertised_info" | cut -d':' -f2)
          shard_advertised_svc_ordinal=$(extract_ordinal_from_object_name "$shard_advertised_svc")
          if [ "$pod_name_ordinal" == "$shard_advertised_svc_ordinal" ]; then
            pod_host_ip=$(parse_host_ip_from_built_in_envs "$pod_name" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_POD_HOST_IP_LIST")
            if [ -z "$pod_host_ip" ]; then
              echo "Failed to get the host ip of the pod $pod_name"
              exit 1
            fi
            if [ "$is_primary" = true ]; then
              initialize_redis_cluster_primary_nodes["$pod_name"]="$pod_host_ip:$shard_advertised_port"
            else
              initialize_redis_cluster_secondary_nodes["$pod_name"]="$pod_host_ip:$shard_advertised_port"
            fi
            initialize_pod_name_to_advertise_host_port_map["$pod_name"]="$pod_host_ip:$shard_advertised_port"
            break
          fi
        done
      done
    else
      local port=$SERVICE_PORT
      pod_name_prefix=$(extract_pod_name_prefix "$pod_name")
      local pod_fqdn="$pod_name.$pod_name_prefix-headless"
      if [ "$is_primary" = true ]; then
        initialize_redis_cluster_primary_nodes["$pod_name"]="$pod_fqdn:$port"
      else
        initialize_redis_cluster_secondary_nodes["$pod_name"]="$pod_fqdn:$port"
      fi
      initialize_pod_name_to_advertise_host_port_map["$pod_name"]="$pod_fqdn:$port"
    fi
  done
}

gen_initialize_redis_cluster_primary_node() {
  gen_initialize_redis_cluster_node true
}

gen_initialize_redis_cluster_secondary_nodes() {
  gen_initialize_redis_cluster_node false
}

initialize_redis_cluster() {
  # initialize all the primary nodes
  gen_initialize_redis_cluster_primary_node
  if [ ${#initialize_redis_cluster_primary_nodes[@]} -eq 0 ]; then
    echo "Failed to get primary nodes"
    exit 1
  fi
  primary_nodes=""
  for primary_pod_name in "${!initialize_redis_cluster_primary_nodes[@]}"; do
    primary_nodes+="${initialize_redis_cluster_primary_nodes[$primary_pod_name]} "
  done
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    initialize_command="redis-cli --cluster create $primary_nodes --cluster-yes"
  else
    initialize_command="redis-cli --cluster create $primary_nodes -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
  fi
  echo "initialize cluster command: $initialize_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
  if ! $initialize_command; then
    echo "Failed to create Redis Cluster"
    exit 1
  fi
  set -x

  # get the first primary node to check the cluster
  first_primary_node=$(echo "$primary_nodes" | awk '{print $1}')
  if redis_cluster_check "$first_primary_node"; then
    echo "Cluster correctly created"
  else
    echo "Failed to create Redis Cluster"
    exit 1
  fi

  # initialize all the secondary nodes
  gen_initialize_redis_cluster_secondary_nodes
  if [ ${#initialize_redis_cluster_secondary_nodes[@]} -eq 0 ]; then
    echo "No secondary nodes to initialize"
    return
  fi
  for secondary_pod_name in "${!initialize_redis_cluster_secondary_nodes[@]}"; do
    secondary_endpoint_with_port=${initialize_redis_cluster_secondary_nodes["$secondary_pod_name"]}
    # shellcheck disable=SC2001
    mapping_primary_pod_name=$(echo "$secondary_pod_name" | sed 's/-[0-9]*$/-0/')
    mapping_primary_endpoint_with_port=${initialize_pod_name_to_advertise_host_port_map["$mapping_primary_pod_name"]}
    if [ -z "$mapping_primary_endpoint_with_port" ]; then
      echo "Failed to find the mapping primary node for secondary node: $secondary_pod_name"
      exit 1
    fi
    mapping_primary_endpoint=$(echo "$mapping_primary_endpoint_with_port" | cut -d':' -f1)
    mapping_primary_port=$(echo "$mapping_primary_endpoint_with_port" | cut -d':' -f2)
    mapping_primary_cluster_id=$(get_cluster_id "$mapping_primary_endpoint" "$mapping_primary_port")
    echo "mapping_primary_fqdn: $mapping_primary_endpoint, mapping_primary_endpoint_with_port: $mapping_primary_endpoint_with_port, mapping_primary_cluster_id: $mapping_primary_cluster_id"
    if [ -z "$mapping_primary_cluster_id" ]; then
      echo "Failed to get the cluster id from cluster nodes of the mapping primary node: $mapping_primary_endpoint_with_port"
      exit 1
    fi
    set +x
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      replicated_command="redis-cli --cluster add-node $secondary_endpoint_with_port $mapping_primary_endpoint_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id"
    else
      replicated_command="redis-cli --cluster add-node $secondary_endpoint_with_port $mapping_primary_endpoint_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "initialize cluster secondary add-node command: $replicated_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
    if ! $replicated_command; then
      echo "Failed to add the node $secondary_pod_name to the cluster in initialize_redis_cluster"
      exit 1
    fi
    set -x
    # waiting for all nodes sync the information
    wait_random_second 5 1
  done
}

scale_out_redis_cluster_shard() {
  init_other_components_and_pods_info "$KB_COMP_NAME" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_LIST" "$KB_CLUSTER_COMPONENT_DELETING_LIST" "$KB_CLUSTER_COMPONENT_UNDELETED_LIST"
  init_current_comp_default_nodes_for_scale_out

  # check the current component shard whether is already scaled out
  if [ ${#scale_out_shard_default_primary_node[@]} -eq 0 ]; then
    echo "Failed to generate primary nodes when scaling out"
    exit 1
  fi
  primary_node_with_port=$(echo "${scale_out_shard_default_primary_node[*]}" | awk '{print $1}')
  primary_node_fqdn=$(echo "$primary_node_with_port" | awk -F ':' '{print $1}')
  primary_node_port=$(echo "$primary_node_with_port" | awk -F ':' '{print $2}')
  mapping_primary_cluster_id=$(get_cluster_id "$primary_node_fqdn" "$primary_node_port")
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

  # add the primary node for the current shard
  for primary_pod_name in "${!scale_out_shard_default_primary_node[@]}"; do
    scale_out_shard_default_primary_node="${scale_out_shard_default_primary_node[$primary_pod_name]}"
    set +x
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      add_node_command="redis-cli --cluster add-node $scale_out_shard_default_primary_node $available_node"
    else
      add_node_command="redis-cli --cluster add-node $scale_out_shard_default_primary_node $available_node -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "scale out shard primary add-node command: $add_node_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
    if ! $add_node_command; then
      echo "Failed to add the node $scale_out_shard_default_primary_node to the cluster"
      exit 1
    fi
    set -x
  done

  # waiting for all nodes sync the information
  wait_random_second 10 5

  # add the other nodes for secondary
  for secondary_pod_name in "${!scale_out_shard_default_other_nodes[@]}"; do
    scale_out_shard_default_other_node="${scale_out_shard_default_other_nodes[$secondary_pod_name]}"
    echo "primary_node_with_port: $primary_node_with_port, primary_node_fqdn: $primary_node_fqdn, mapping_primary_cluster_id: $mapping_primary_cluster_id"
    set +x
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      replicated_command="redis-cli --cluster add-node $scale_out_shard_default_other_node $primary_node_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id"
    else
      replicated_command="redis-cli --cluster add-node $scale_out_shard_default_other_node $primary_node_with_port --cluster-slave --cluster-master-id $mapping_primary_cluster_id -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "scale out shard secondary replicated command: $replicated_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
    if ! $replicated_command; then
      echo "Failed to add the node $scale_out_shard_default_other_node to the cluster"
      exit 1
    fi
    set -x
  done

  # do the reshard
  # TODO: optimize the number of reshard slots according to the cluster status
  total_slots=16384
  current_comp_pod_count=$(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' '\n' | grep -c "^$KB_CLUSTER_COMP_NAME-")
  all_comp_pod_count=$(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' '\n' | grep -c ".*")
  shard_count=$((all_comp_pod_count / current_comp_pod_count))
  slots_per_shard=$((total_slots / shard_count))
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      reshard_command="redis-cli --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard --cluster-yes"
  else
      reshard_command="redis-cli --cluster reshard $primary_node_with_port --cluster-from all --cluster-to $mapping_primary_cluster_id --cluster-slots $slots_per_shard -a $REDIS_DEFAULT_PASSWORD --cluster-yes"
  fi
  echo "scale out shard reshard command: $reshard_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
  if ! $reshard_command
  then
      echo "Failed to reshard the cluster"
      exit 1
  fi
  set -x

  # rebalance the cluster
  #  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
  #      rebalance_command="redis-cli --cluster rebalance $primary_node_with_port --cluster-timeout 3000 --cluster-simulate"
  #  else
  #      rebalance_command="redis-cli --cluster rebalance $primary_node_with_port --cluster-timeout 3000 --cluster-simulate -a $REDIS_DEFAULT_PASSWORD"
  #  fi
  #  if ! $rebalance_command
  #  then
  #      echo "Failed to rebalance the cluster"
  #      exit 1
  #  fi
}

scale_in_redis_cluster_shard() {
  # check KB_CLUSTER_COMPONENT_IS_SCALING_IN env
  if [ -z "$KB_CLUSTER_COMPONENT_IS_SCALING_IN" ]; then
    echo "The KB_CLUSTER_COMPONENT_IS_SCALING_IN env is not set, skip scaling in"
    exit 0
  fi

  # init information for the other components and pods
  init_other_components_and_pods_info "$KB_COMP_NAME" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_LIST" "$KB_CLUSTER_COMPONENT_DELETING_LIST" "$KB_CLUSTER_COMPONENT_UNDELETED_LIST"
  available_node=$(find_exist_available_node)
  available_node_fqdn=$(echo "$available_node" | awk -F ':' '{print $1}')
  available_node_port=$(echo "$available_node" | awk -F ':' '{print $2}')
  get_current_comp_nodes_for_scale_in "$available_node_fqdn" "$available_node_port"

  # Check if the number of shards in the cluster is less than 3 after scaling down.
  current_comp_pod_count=0
  for pod_name in $(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' ' '); do
    if [[ "$pod_name" == "$KB_CLUSTER_COMP_NAME"* ]]; then
      current_comp_pod_count=$((current_comp_pod_count + 1))
    fi
  done
  shard_count=$((${#other_undeleted_component_nodes[@]} / current_comp_pod_count))
  if [ $shard_count -lt 3 ]; then
    echo "The number of shards in the cluster is less than 3 after scaling in, please check."
    exit 1
  fi

  # set the current component slot to 0 by rebalance command
  for primary_node in "${current_comp_primary_node[@]}"; do
    primary_node_fqdn=$(echo "$primary_node" | awk -F ':' '{print $1}')
    primary_node_port=$(echo "$primary_node" | awk -F ':' '{print $2}')
    primary_node_cluster_id=$(get_cluster_id "$primary_node_fqdn" "$primary_node_port")
    set +x
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      rebalance_command="redis-cli --cluster rebalance $primary_node --cluster-weight $primary_node_cluster_id=0 --cluster-yes "
    else
      rebalance_command="redis-cli --cluster rebalance $primary_node --cluster-weight $primary_node_cluster_id=0 --cluster-yes -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "set current component slot to 0 by rebalance command: $rebalance_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
    if ! $rebalance_command
    then
      echo "Failed to rebalance the cluster for the current component when scaling in"
      exit 1
    fi
    set -x
  done

  wait_random_second 10 5

  # delete the current component nodes from the cluster
  for node_to_del in "${current_comp_primary_node[@]}" "${current_comp_other_nodes[@]}"; do
    node_to_del_fqdn=$(echo "$node_to_del" | awk -F ':' '{print $1}')
    node_to_del_port=$(echo "$node_to_del" | awk -F ':' '{print $2}')
    node_to_del_cluster_id=$(get_cluster_id "$node_to_del_fqdn" "$node_to_del_port")
    set +x
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      del_node_command="redis-cli --cluster del-node $available_node $node_to_del_cluster_id -p $SERVICE_PORT"
    else
      del_node_command="redis-cli --cluster del-node $available_node $node_to_del_cluster_id -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD"
    fi
    echo "del-node command: $del_node_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
    if ! $del_node_command
    then
      echo "Failed to delete the node $node_to_del from the cluster when scaling in"
      exit 1
    fi
    set -x
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
