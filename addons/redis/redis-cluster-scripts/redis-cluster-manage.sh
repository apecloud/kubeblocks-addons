#!/bin/bash

# shellcheck disable=SC2128
# shellcheck disable=SC2207
# shellcheck disable=SC1090

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
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

# declare the global variables for initialize redis cluster
declare -gA initialize_redis_cluster_primary_nodes
declare -gA initialize_redis_cluster_secondary_nodes
declare -gA initialize_pod_name_to_advertise_host_port_map

# declare the global variables for scale out redis cluster shard
declare -gA scale_out_shard_default_primary_node
declare -gA scale_out_shard_default_other_nodes

load_redis_cluster_common_utils() {
  # the common.sh and redis-cluster-common.sh scripts are defined in the redis-cluster-scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/common.sh"
  redis_cluster_common_library_file="/scripts/redis-cluster-common.sh"
  source "${kblib_common_library_file}"
  source "${redis_cluster_common_library_file}"
}

# initialize the other component and pods info
init_other_components_and_pods_info() {
  local current_component="$1"
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
  echo "init other components and pods info, current component: $current_component"
  # filter out the components of the given component
  IFS=',' read -ra components <<< "$all_component_list"
  IFS=',' read -ra deleting_components <<< "$all_deleting_component_list"
  IFS=',' read -ra undeleted_components <<< "$all_undeleted_component_list"
  for comp in "${components[@]}"; do
    if equals "$comp" "$current_component"; then
      echo "skip the component $comp as it is the current component"
      continue
    fi
    other_components+=("$comp")
  done
  for comp in "${deleting_components[@]}"; do
    if equals "$comp" "$current_component"; then
      echo "skip the component $comp as it is the current component"
      continue
    fi
    other_deleting_components+=("$comp")
  done
  for comp in "${undeleted_components[@]}"; do
    if equals "$comp" "$current_component"; then
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
    for deleting_comp in "${deleting_components[@]}"; do
      if echo "${pod_names[$index]}" | grep "$deleting_comp-"; then
        echo "skip the pod ${pod_names[$index]} as it belongs the deleting component $deleting_comp"
        continue 2
      fi
    done

    other_undeleted_component_pod_ips+=("${pod_ips[$index]}")
    other_undeleted_component_pod_names+=("${pod_names[$index]}")

    local service_port
    service_port=$(get_pod_service_port_by_network_mode "${pod_names[$index]}")

    # TODO: resolve the pod fqdn from the Vars
    pod_name_prefix=$(extract_pod_name_prefix "${pod_names[$index]}")
    pod_fqdn="${pod_names[$index]}.$pod_name_prefix-headless.$CLUSTER_NAMESPACE.svc.cluster.local"
    other_undeleted_component_nodes+=("$pod_fqdn:$service_port")
  done

  echo "other_components: ${other_components[*]}"
  echo "other_deleting_components: ${other_deleting_components[*]}"
  echo "other_undeleted_components: ${other_undeleted_components[*]}"
  echo "other_undeleted_component_pod_ips: ${other_undeleted_component_pod_ips[*]}"
  echo "other_undeleted_component_pod_names: ${other_undeleted_component_pod_names[*]}"
  echo "other_undeleted_component_nodes: ${other_undeleted_component_nodes[*]}"
}

find_exist_available_node() {
  local node_ip
  local node_port
  for node in "${other_undeleted_component_nodes[@]}"; do
    # the $node is the headless address by default, we should get the real node address from cluster nodes
    node_ip=$(echo "$node" | cut -d':' -f1)
    node_port=$(echo "$node" | cut -d':' -f2)
    if check_slots_covered "$node" "$node_port"; then
      # the $node is the headless address by default, we should get the real node address from cluster nodes
      cluster_nodes_info=$(get_cluster_nodes_info "$node_ip" "$node_port")
      status=$?
      if [ $status -ne 0 ]; then
        echo "Failed to get cluster nodes info in find_exist_available_node" >&2
        exit 1
      fi
      # grep my self node and return the nodeIp:port(it may be the announceIp and announcePort, for example when cluster enable NodePort/LoadBalancer service)
      available_node_with_port=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $2}' | cut -d'@' -f1)
      echo "$available_node_with_port"
      return
    fi
  done
  echo ""
}

extract_pod_name_prefix() {
  local pod_name="$1"
  # shellcheck disable=SC2001
  prefix=$(echo "$pod_name" | sed 's/-[0-9]*$//')
  echo "$prefix"
}

# get the current component primary node and other nodes for scale in
get_current_comp_nodes_for_scale_in() {

  parse_node_line_info() {
    local line="$1"

    local node_ip_port_fields
    # 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local
    node_ip_port_fields=$(echo "$line" | awk '{print $2}')

    local node_ip_port
    # ip:port without bus port
    node_ip_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}')

    local node_ip
    node_ip=$(echo "$node_ip_port" | cut -d':' -f1)

    local node_port
    node_port=$(echo "$node_ip_port" | cut -d':' -f2)

    local node_fqdn
    # redis-shard-sxj-0.redis-shard-sxj-headless.default.svc
    node_fqdn=$(echo "$line" | awk '{print $2}' | awk -F ',' '{print $2}')

    local node_role
    node_role=$(echo "$line" | awk '{print $3}')

    echo "$node_ip $node_port $node_fqdn $node_role"
  }

  get_node_address_by_network_mode() {
    local network_mode="$1"
    local node_ip="$2"
    local node_port="$3"
    local node_fqdn="$4"

    case "$network_mode" in
      "advertised_svc")
        echo "$node_ip:$node_port"
        ;;
      "host_network")
        echo "$node_ip:$REDIS_CLUSTER_HOST_NETWORK_PORT"
        ;;
      *)
        # shellcheck disable=SC2153
        echo "$node_fqdn:$SERVICE_PORT"
        ;;
    esac
  }

  categorize_node() {
    local node_address="$1"
    local node_fqdn="$2"
    local node_role="$3"

    if [[ "$node_fqdn" =~ "$CURRENT_SHARD_COMPONENT_NAME"* ]]; then
      if [[ "$node_role" =~ "master" ]]; then
        current_comp_primary_node+=("$node_address")
      else
        current_comp_other_nodes+=("$node_address")
      fi
    fi
  }

  local cluster_node="$1"
  local cluster_node_port="$2"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in get_current_comp_nodes_for_scale_in" >&2
    return 1
  fi

  current_comp_primary_node=()
  current_comp_other_nodes=()

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -eq 1 ]; then
    echo "Cluster nodes info contains only one line, returning..."
    return
  fi

  # determine network mode
  local network_mode="default"
  if ! is_empty "$CURRENT_SHARD_ADVERTISED_PORT"; then
    network_mode="advertised_svc"
  elif ! is_empty "$REDIS_CLUSTER_HOST_NETWORK_PORT"; then
    network_mode="host_network"
  fi

  # the output of line is like:
  # 1. using the pod fqdn as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # 2. using the nodeport or lb ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:31000@31888,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # 3. using the host network ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:1050@1051,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  while read -r line; do
    local node_info
    node_info=$(parse_node_line_info "$line")
    read -r node_ip node_port node_fqdn node_role <<< "$node_info"

    local node_address
    node_address=$(get_node_address_by_network_mode "$network_mode" "$node_ip" "$node_port" "$node_fqdn")

    categorize_node "$node_address" "$node_fqdn" "$node_role"
  done <<< "$cluster_nodes_info"

  echo "current_comp_primary_node: ${current_comp_primary_node[*]}"
  echo "current_comp_other_nodes: ${current_comp_other_nodes[*]}"
}

# init the current shard component default primary and secondary nodes for scale out shard.
# TODO: if advertised address is enable and instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
# TODO: remove the dependency of the built-in envs like KB_CLUSTER_COMPONENT_XXXX
init_current_comp_default_nodes_for_scale_out() {
  # categorize the scale out node map
  categorize_scale_out_node_map() {
    local pod_name="$1"
    local node_address="$2"
    local pod_ordinal="$3"

    if equals "$pod_ordinal" "$min_lexicographical_pod_ordinal"; then
      scale_out_shard_default_primary_node["$pod_name"]="$node_address"
    else
      scale_out_shard_default_other_nodes["$pod_name"]="$node_address"
    fi
  }

  # handle the advertised service network mode (currently only support NodePort service type
  handle_advertised_svc_network_mode() {
    local pod_name="$1"
    local pod_name_ordinal="$2"

    local old_ifs="$IFS"
    IFS=','
    set -f
    read -ra advertised_infos <<< "$CURRENT_SHARD_ADVERTISED_PORT"
    set +f
    IFS="$old_ifs"

    local found_advertised_port=false
    for advertised_info in "${advertised_infos[@]}"; do
      local advertised_svc advertised_port advertised_svc_ordinal
      advertised_svc=$(echo "$advertised_info" | cut -d':' -f1)
      advertised_port=$(echo "$advertised_info" | cut -d':' -f2)
      advertised_svc_ordinal=$(extract_obj_ordinal "$advertised_svc")

      if [ "$pod_name_ordinal" == "$advertised_svc_ordinal" ]; then
        local pod_host_ip
        pod_host_ip=$(parse_host_ip_from_built_in_envs "$pod_name" "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST")
        status=$?
        if is_empty "$pod_host_ip" || [ $status -ne 0 ]; then
          echo "Failed to get host ip of pod $pod_name" >&2
          return 1
        fi

        categorize_scale_out_node_map "$pod_name" "$pod_host_ip:$advertised_port" "$pod_name_ordinal"
        found_advertised_port=true
        break
      fi
    done

    if [ "$found_advertised_port" = false ]; then
      echo "Advertised port not found for pod $pod_name" >&2
      return 1
    fi
    return 0
  }

  # handle the host network mode
  handle_host_network_mode() {
    local pod_name="$1"
    local pod_name_ordinal="$2"

    local pod_host_ip
    pod_host_ip=$(parse_host_ip_from_built_in_envs "$pod_name" "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST")
    if is_empty "$pod_host_ip"; then
      echo "Failed to get host ip of pod $pod_name in host network mode" >&2
      return 1
    fi

    categorize_scale_out_node_map "$pod_name" "$pod_host_ip:$REDIS_CLUSTER_HOST_NETWORK_PORT" "$pod_name_ordinal"
    return 0
  }

  # handle the default network mode
  handle_default_network_mode() {
    local pod_name="$1"
    local pod_name_ordinal="$2"

    local pod_fqdn
    local port="$SERVICE_PORT"

    pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$pod_name")
    if is_empty "$pod_fqdn"; then
      echo "Error: Failed to get pod $pod_name fqdn from list: $CURRENT_SHARD_POD_FQDN_LIST" >&2
      return 1
    fi

    categorize_scale_out_node_map "$pod_name" "$pod_fqdn:$port" "$pod_name_ordinal"
    return 0
  }

  process_pod_by_network_mode() {
    local network_mode="$1"
    local pod_name="$2"
    local pod_name_ordinal="$3"

    case "$network_mode" in
      "advertised_svc")
        handle_advertised_svc_network_mode "$pod_name" "$pod_name_ordinal"
        ;;
      "host_network")
        handle_host_network_mode "$pod_name" "$pod_name_ordinal"
        ;;
      *)
        handle_default_network_mode "$pod_name" "$pod_name_ordinal"
        ;;
    esac
    return $?
  }

  local min_lexicographical_pod_name
  local min_lexicographical_pod_ordinal
  min_lexicographical_pod_name=$(min_lexicographical_order_pod "$KB_CLUSTER_COMPONENT_POD_NAME_LIST")
  min_lexicographical_pod_ordinal=$(extract_obj_ordinal "$min_lexicographical_pod_name")
  if is_empty "$min_lexicographical_pod_ordinal"; then
    echo "Failed to get the ordinal of the min lexicographical pod $min_lexicographical_pod_name in init_current_comp_default_nodes_for_scale_out" >&2
    return 1
  fi

  # determine network mode
  local network_mode="default"
  if ! is_empty "$CURRENT_SHARD_ADVERTISED_PORT"; then
    network_mode="advertised_svc"
  elif ! is_empty "$REDIS_CLUSTER_HOST_NETWORK_PORT"; then
    network_mode="host_network"
  fi

  for pod_name in $(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' ' '); do
    local pod_name_ordinal
    pod_name_ordinal=$(extract_obj_ordinal "$pod_name")
    process_pod_by_network_mode "$network_mode" "$pod_name" "$pod_name_ordinal" || return 1
  done
  return 0
}

# initialize the redis cluster primary and secondary nodes, use the min lexicographical pod of each shard as the primary nodes by default.
gen_initialize_redis_cluster_node() {
  local is_primary=$1

  categorize_node_maps() {
    local pod_name="$1"
    local host="$2"
    local port="$3"
    local is_primary="$4"

    local node_addr="$host:$port"

    if equals "$is_primary" "true"; then
      initialize_redis_cluster_primary_nodes["$pod_name"]="$node_addr"
    else
      initialize_redis_cluster_secondary_nodes["$pod_name"]="$node_addr"
    fi
    initialize_pod_name_to_advertise_host_port_map["$pod_name"]="$node_addr"
  }

  # determine if pod should be processed based on primary/secondary role
  should_process_pod() {
    local is_primary="$1"
    local pod_ordinal="$2"
    local min_pod_ordinal="$3"

    if [ "$is_primary" = "true" ]; then
      [ "$pod_ordinal" = "$min_pod_ordinal" ]
    else
      [ "$pod_ordinal" != "$min_pod_ordinal" ]
    fi
  }

  # Initialize node with advertised service configuration
  initialize_advertised_svc_node() {
    local pod_name="$1"
    local pod_name_ordinal="$2"
    local is_primary="$3"

    local pod_host_ip
    pod_host_ip=$(parse_host_ip_from_built_in_envs "$pod_name" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_POD_HOST_IP_LIST") || {
      echo "Failed to get host IP for pod: $pod_name" >&2
      return 1
    }

    ## the value format of ALL_SHARDS_ADVERTISED_PORT is "shard-98x@redis-shard-98x-redis-advertised-0:32024,redis-shard-98x-redis-advertised-1:31318.shard-cq7@redis-shard-cq7-redis-advertised-0:31828,redis-shard-cq7-redis-advertised-1:32000"
    local old_ifs="$IFS"
    IFS='.'
    set -f
    local shards
    read -ra shards <<< "$ALL_SHARDS_ADVERTISED_PORT"
    set +f
    IFS="$old_ifs"

    local shard
    for shard in "${shards[@]}"; do
      local shard_name
      shard_name=$(echo "$shard" | cut -d'@' -f1)

      # skip if pod doesn't belong to current shard
      if ! echo "$pod_name" | grep -q "$shard_name"; then
        continue
      fi

      # shard_advertised_infos like "redis-shard-98x-redis-advertised-0:32024,redis-shard-98x-redis-advertised-1:31318"
      local old_ifs="$IFS"
      IFS=','
      set -f
      local shard_advertised_infos
      read -ra shard_advertised_infos <<< "$(echo "$shard" | cut -d'@' -f2)"
      set +f
      IFS="$old_ifs"

      local shard_advertised_info
      for shard_advertised_info in "${shard_advertised_infos[@]}"; do
        local shard_advertised_svc
        local shard_advertised_port
        local shard_advertised_svc_ordinal

        shard_advertised_svc=$(echo "$shard_advertised_info" | cut -d':' -f1)
        shard_advertised_port=$(echo "$shard_advertised_info" | cut -d':' -f2)
        shard_advertised_svc_ordinal=$(extract_obj_ordinal "$shard_advertised_svc")

        if [ "$pod_name_ordinal" = "$shard_advertised_svc_ordinal" ]; then
          categorize_node_maps "$pod_name" "$pod_host_ip" "$shard_advertised_port" "$is_primary"
          return 0
        fi
      done
    done
    return 0
  }

  # Initialize node with host network configuration
  initialize_host_network_node() {
    local pod_name="$1"
    local is_primary="$2"

    local pod_host_ip
    pod_host_ip=$(parse_host_ip_from_built_in_envs "$pod_name" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_POD_HOST_IP_LIST") || {
      echo "Failed to get host IP for pod: $pod_name" >&2
      return 1
    }

    local service_port
    service_port=$(get_pod_service_port_by_network_mode "${pod_name}") || {
      echo "Failed to get service port for pod: $pod_name" >&2
      return 1
    }

    categorize_node_maps "$pod_name" "$pod_host_ip" "$service_port" "$is_primary"
    return 0
  }

  # Initialize node with default network configuration
  initialize_default_network_node() {
    local pod_name="$1"
    local is_primary="$2"

    local service_port
    service_port=$(get_pod_service_port_by_network_mode "${pod_name}") || {
      echo "Failed to get service_port for pod: $pod_name" >&2
      return 1
    }

    local all_shard_pod_fqdns
    all_shard_pod_fqdns=$(get_all_shards_pod_fqdns) || {
      echo "Failed to get all shard pod FQDNs" >&2
      return 1
    }

    local pod_fqdn
    pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$all_shard_pod_fqdns" "$pod_name") || {
      echo "Failed to get FQDN for pod: $pod_name" >&2
      return 1
    }

    categorize_node_maps "$pod_name" "$pod_fqdn" "$service_port" "$is_primary"
    return 0
  }

  # determine cluster network mode
  local network_mode="default"
  if ! is_empty "$ALL_SHARDS_ADVERTISED_PORT"; then
    network_mode="advertised_svc"
  elif ! is_empty "$REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT"; then
    network_mode="host_network"
  fi

  # get and validate the min lexicographical pod name and ordinal
  local min_lexicographical_pod_name
  local min_lexicographical_pod_ordinal
  min_lexicographical_pod_name=$(min_lexicographical_order_pod "$KB_CLUSTER_POD_NAME_LIST")
  min_lexicographical_pod_ordinal=$(extract_obj_ordinal "$min_lexicographical_pod_name")
  if is_empty "$min_lexicographical_pod_ordinal"; then
    echo "Failed to get the ordinal of the min lexicographical pod $min_lexicographical_pod_name in gen_initialize_redis_cluster_node" >&2
    return 1
  fi

  local pod_name
  for pod_name in $(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' ' '); do
    local pod_name_ordinal
    pod_name_ordinal=$(extract_obj_ordinal "$pod_name") || continue

    # skip pods based on primary/secondary role
    if ! should_process_pod "$is_primary" "$pod_name_ordinal" "$min_lexicographical_pod_ordinal"; then
      continue
    fi

    # initialize pod based on network mode
    case "$network_mode" in
      "advertised_svc")
        initialize_advertised_svc_node "$pod_name" "$pod_name_ordinal" "$is_primary" || return 1
        ;;
      "host_network")
        initialize_host_network_node "$pod_name" "$is_primary" || return 1
        ;;
      "default")
        initialize_default_network_node "$pod_name" "$is_primary" || return 1
        ;;
    esac
  done
  return 0
}

gen_initialize_redis_cluster_primary_node() {
  gen_initialize_redis_cluster_node "true"
}

gen_initialize_redis_cluster_secondary_nodes() {
  gen_initialize_redis_cluster_node "false"
}

initialize_redis_cluster() {
  if is_empty "$KB_CLUSTER_POD_NAME_LIST" || is_empty "$KB_CLUSTER_POD_HOST_IP_LIST"; then
    echo "Error: Required environment variable KB_CLUSTER_POD_NAME_LIST and KB_CLUSTER_POD_HOST_IP_LIST are not set when initializing redis cluster" >&2
    return 1
  fi

  # initialize all the primary nodes
  gen_initialize_redis_cluster_primary_node
  if [ ${#initialize_redis_cluster_primary_nodes[@]} -eq 0 ] || [ ${#initialize_redis_cluster_primary_nodes[@]} -lt 3 ]; then
    echo "Failed to get primary nodes or the primary nodes count is less than 3" >&2
    return 1
  fi
  local primary_nodes=""
  for primary_pod_name in "${!initialize_redis_cluster_primary_nodes[@]}"; do
    primary_nodes+="${initialize_redis_cluster_primary_nodes[$primary_pod_name]} "
  done

  if create_redis_cluster "$primary_nodes"; then
    echo "Redis cluster initialized primary nodes successfully, cluster nodes: $primary_nodes"
  else
    echo "Failed to create redis cluster when initializing" >&2
    return 1
  fi

  # get the first primary node to check the cluster
  first_primary_node=$(echo "$primary_nodes" | awk '{print $1}')
  if check_slots_covered "$first_primary_node" "$SERVICE_PORT"; then
    echo "Redis cluster check primary nodes slots covered successfully."
  else
    echo "Failed to create redis cluster when checking slots covered" >&2
    return 1
  fi

  # initialize all the secondary nodes
  gen_initialize_redis_cluster_secondary_nodes
  if [ ${#initialize_redis_cluster_secondary_nodes[@]} -eq 0 ]; then
    echo "No secondary nodes to initialize"
    return 0
  fi
  for secondary_pod_name in "${!initialize_redis_cluster_secondary_nodes[@]}"; do
    secondary_endpoint_with_port=${initialize_redis_cluster_secondary_nodes["$secondary_pod_name"]}
    # shellcheck disable=SC2001
    mapping_primary_pod_name=$(echo "$secondary_pod_name" | sed 's/-[0-9]*$/-0/')
    mapping_primary_endpoint_with_port=${initialize_pod_name_to_advertise_host_port_map["$mapping_primary_pod_name"]}
    if is_empty "$mapping_primary_endpoint_with_port"; then
      echo "Failed to find the mapping primary node for secondary node: $secondary_pod_name" >&2
      return 1
    fi
    mapping_primary_endpoint=$(echo "$mapping_primary_endpoint_with_port" | cut -d':' -f1)
    mapping_primary_port=$(echo "$mapping_primary_endpoint_with_port" | cut -d':' -f2)
    mapping_primary_cluster_id=$(get_cluster_id "$mapping_primary_endpoint" "$mapping_primary_port")
    echo "mapping_primary_fqdn: $mapping_primary_endpoint, mapping_primary_endpoint_with_port: $mapping_primary_endpoint_with_port, mapping_primary_cluster_id: $mapping_primary_cluster_id"
    if is_empty "$mapping_primary_cluster_id"; then
      echo "Failed to get the cluster id from cluster nodes of the mapping primary node: $mapping_primary_endpoint_with_port" >&2
      return 1
    fi
    replicated_output=$(secondary_replicated_to_primary "$secondary_endpoint_with_port" "$mapping_primary_endpoint_with_port" "$mapping_primary_cluster_id")
    status=$?
    if [ $status -ne 0 ] ; then
      echo "Failed to initialize the secondary node $secondary_pod_name, secondary replicated output: $replicated_output" >&2
      return 1
    fi
    echo "Redis cluster initialized secondary node $secondary_pod_name successfully"
    # waiting for all nodes sync the information
    sleep_when_ut_mode_false 5
  done
  return 0
}

scale_out_redis_cluster_shard() {
  if is_empty "$CURRENT_SHARD_COMPONENT_SHORT_NAME" || is_empty "$KB_CLUSTER_POD_NAME_LIST" || is_empty "$KB_CLUSTER_POD_HOST_IP_LIST" || is_empty "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" || is_empty "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST"; then
    echo "Error: Required environment variable CURRENT_SHARD_COMPONENT_SHORT_NAME, KB_CLUSTER_POD_NAME_LIST, KB_CLUSTER_POD_HOST_IP_LIST, KB_CLUSTER_COMPONENT_POD_NAME_LIST and KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set when scale out redis cluster shard" >&2
    return 1
  fi

  init_other_components_and_pods_info "$CURRENT_SHARD_COMPONENT_SHORT_NAME" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_LIST" "$KB_CLUSTER_COMPONENT_DELETING_LIST" "$KB_CLUSTER_COMPONENT_UNDELETED_LIST"
  if init_current_comp_default_nodes_for_scale_out; then
    echo "Redis cluster scale out shard default primary and secondary nodes successfully"
  else
    echo "Failed to initialize the default primary and secondary nodes for scale out" >&2
    return 1
  fi

  # check the current component shard whether is already scaled out
  if [ ${#scale_out_shard_default_primary_node[@]} -eq 0 ]; then
    echo "Failed to generate primary nodes when scaling out" >&2
    return 1
  fi
  primary_node_with_port=$(echo "${scale_out_shard_default_primary_node[*]}" | awk '{print $1}')
  primary_node_fqdn=$(echo "$primary_node_with_port" | awk -F ':' '{print $1}')
  primary_node_port=$(echo "$primary_node_with_port" | awk -F ':' '{print $2}')
  mapping_primary_cluster_id=$(get_cluster_id "$primary_node_fqdn" "$primary_node_port")
  if check_slots_covered "$primary_node_with_port" "$SERVICE_PORT"; then
    echo "The current component shard is already scaled out, no need to scale out again."
    return 0
  fi

  # find the exist available node which is not in the current component
  available_node=$(find_exist_available_node)
  if is_empty "$available_node"; then
    echo "No exist available node found or cluster status is not ok" >&2
    return 1
  fi

  # add the primary node for the current shard
  local scale_out_shard_default_primary
  for primary_pod_name in "${!scale_out_shard_default_primary_node[@]}"; do
    scale_out_shard_default_primary="${scale_out_shard_default_primary_node[$primary_pod_name]}"
    if scale_out_shard_primary_join_cluster "$scale_out_shard_default_primary" "$available_node"; then
      echo "Redis cluster scale out shard primary node $primary_pod_name successfully"
    else
      echo "Failed to scale out shard primary node $primary_pod_name" >&2
      return 1
    fi
  done

  # waiting for all nodes sync the information
  sleep_when_ut_mode_false 5

  # add the secondary nodes to replicate the primary node
  local scale_out_shard_secondary_node
  for secondary_pod_name in "${!scale_out_shard_default_other_nodes[@]}"; do
    scale_out_shard_secondary_node="${scale_out_shard_default_other_nodes[$secondary_pod_name]}"
    echo "primary_node_with_port: $primary_node_with_port, primary_node_fqdn: $primary_node_fqdn, mapping_primary_cluster_id: $mapping_primary_cluster_id"
    if secondary_replicated_to_primary "$scale_out_shard_secondary_node" "$primary_node_with_port" "$mapping_primary_cluster_id"; then
      echo "Redis cluster scale out shard secondary node $secondary_pod_name successfully"
    else
      echo "Failed to scale out shard secondary node $secondary_pod_name" >&2
      return 1
    fi
  done

  # do the reshard
  # TODO: optimize the number of reshard slots according to the cluster status
  local total_slots
  local current_comp_pod_count
  local all_comp_pod_count
  local shard_count
  local slots_per_shard
  total_slots=16384
  current_comp_pod_count=$(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' '\n' | grep -c "^$CURRENT_SHARD_COMPONENT_NAME-")
  all_comp_pod_count=$(echo "$KB_CLUSTER_POD_NAME_LIST" | tr ',' '\n' | grep -c ".*")
  shard_count=$((all_comp_pod_count / current_comp_pod_count))
  slots_per_shard=$((total_slots / shard_count))
  if scale_out_shard_reshard "$primary_node_with_port" "$mapping_primary_cluster_id" "$slots_per_shard"; then
    echo "Redis cluster scale out shard reshard successfully"
  else
    echo "Failed to scale out shard reshard" >&2
    return 1
  fi

  # TODO: rebalance the cluster
  return 0
}

scale_in_redis_cluster_shard() {
  # check KB_CLUSTER_COMPONENT_IS_SCALING_IN env
  if is_empty "$KB_CLUSTER_COMPONENT_IS_SCALING_IN"; then
    echo "The KB_CLUSTER_COMPONENT_IS_SCALING_IN env is not set, skip scaling in"
    return 0
  fi

  if is_empty "$CURRENT_SHARD_COMPONENT_SHORT_NAME" || is_empty "$KB_CLUSTER_POD_NAME_LIST" || is_empty "$KB_CLUSTER_POD_HOST_IP_LIST" || is_empty "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" || is_empty "$KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST"; then
    echo "Error: Required environment variable CURRENT_SHARD_COMPONENT_SHORT_NAME, KB_CLUSTER_POD_NAME_LIST, KB_CLUSTER_POD_HOST_IP_LIST, KB_CLUSTER_COMPONENT_POD_NAME_LIST and KB_CLUSTER_COMPONENT_POD_HOST_IP_LIST are not set when scale in redis cluster shard" >&2
    return 1
  fi

  # init information for the other components and pods
  init_other_components_and_pods_info "$CURRENT_SHARD_COMPONENT_SHORT_NAME" "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST" "$KB_CLUSTER_COMPONENT_LIST" "$KB_CLUSTER_COMPONENT_DELETING_LIST" "$KB_CLUSTER_COMPONENT_UNDELETED_LIST"
  available_node=$(find_exist_available_node)
  available_node_fqdn=$(echo "$available_node" | awk -F ':' '{print $1}')
  available_node_port=$(echo "$available_node" | awk -F ':' '{print $2}')
  get_current_comp_nodes_for_scale_in "$available_node_fqdn" "$available_node_port"

  # Check if the number of shards in the cluster is less than 3 after scaling down.
  current_comp_pod_count=0
  for pod_name in $(echo "$KB_CLUSTER_COMPONENT_POD_NAME_LIST" | tr ',' ' '); do
    if [[ "$pod_name" == "$CURRENT_SHARD_COMPONENT_NAME"* ]]; then
      current_comp_pod_count=$((current_comp_pod_count + 1))
    fi
  done
  shard_count=$((${#other_undeleted_component_nodes[@]} / current_comp_pod_count))
  if [ $shard_count -lt 3 ]; then
    echo "The number of shards in the cluster is less than 3 after scaling in, please check." >&2
    return 1
  fi

  # set the current shard component slot to 0 by rebalance command
  for primary_node in "${current_comp_primary_node[@]}"; do
    primary_node_fqdn=$(echo "$primary_node" | awk -F ':' '{print $1}')
    primary_node_port=$(echo "$primary_node" | awk -F ':' '{print $2}')
    primary_node_cluster_id=$(get_cluster_id "$primary_node_fqdn" "$primary_node_port")
    if scale_in_shard_rebalance_to_zero "$primary_node" "$primary_node_cluster_id"; then
      echo "Redis cluster scale in shard rebalance to zero successfully"
    else
      echo "Failed to rebalance the cluster for the current component when scaling in" >&2
      return 1
    fi
  done

  sleep_when_ut_mode_false 5

  # delete the current shard component nodes from the cluster
  for node_to_del in "${current_comp_primary_node[@]}" "${current_comp_other_nodes[@]}"; do
    node_to_del_fqdn=$(echo "$node_to_del" | awk -F ':' '{print $1}')
    node_to_del_port=$(echo "$node_to_del" | awk -F ':' '{print $2}')
    node_to_del_cluster_id=$(get_cluster_id "$node_to_del_fqdn" "$node_to_del_port")
    if scale_in_shard_del_node "$available_node" "$node_to_del_cluster_id"; then
      echo "Redis cluster scale in shard delete node $node_to_del successfully"
    else
      echo "Failed to delete the node $node_to_del from the cluster when scaling in" >&2
      return 1
    fi
  done
  return 0
}

initialize_or_scale_out_redis_cluster() {
  # TODO: remove random sleep, it's a workaround for the multi components initialization parallelism issue
  sleep_random_second_when_ut_mode_false 10 1

  if is_empty "$KB_CLUSTER_POD_IP_LIST" || is_empty "$KB_CLUSTER_POD_NAME_LIST"; then
    echo "Error: Required environment variable KB_CLUSTER_POD_IP_LIST and KB_CLUSTER_POD_NAME_LIST and SERVICE_PORT is not set." >&2
    return 1
  fi

  # if the cluster is not initialized, initialize it
  if ! check_cluster_initialized "$KB_CLUSTER_POD_IP_LIST" "$KB_CLUSTER_POD_NAME_LIST"; then
    echo "Redis Cluster not initialized, initializing..."
    if initialize_redis_cluster; then
      echo "Redis Cluster initialized successfully"
    else
      echo "Failed to initialize Redis Cluster" >&2
      return 1
    fi
  else
    echo "Redis Cluster already initialized, scaling out the shard..."
    if scale_out_redis_cluster_shard; then
      echo "Redis Cluster scale out shard successfully"
    else
      echo "Failed to scale out Redis Cluster shard" >&2
      return 1
    fi
  fi
  return 0
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
if [ $# -eq 1 ]; then
  load_redis_cluster_common_utils
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
    if initialize_or_scale_out_redis_cluster; then
      echo "Redis Cluster initialized or scale out shard successfully"
    else
      echo "Failed to initialize or scale out Redis Cluster shard" >&2
      exit 1
    fi
    exit 0
    ;;
  --pre-terminate)
    if scale_in_redis_cluster_shard; then
      echo "Redis Cluster scale in shard successfully"
    else
      echo "Failed to scale in Redis Cluster shard" >&2
      exit 1
    fi
    exit 0
    ;;
  *)
    echo "Error: invalid option '$1'"
    exit 1
    ;;
  esac
fi
