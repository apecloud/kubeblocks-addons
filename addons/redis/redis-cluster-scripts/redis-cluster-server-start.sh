#!/bin/bash

# shellcheck disable=SC2153
# shellcheck disable=SC2207
# shellcheck disable=SC2034
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
# you should set ut_mode="true" when you want to run the script in shellspec file.
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

service_port=6379
cluster_bus_port=16379
redis_template_conf="/etc/conf/redis.conf"
redis_real_conf="/etc/redis/redis.conf"
redis_acl_file="/data/users.acl"
redis_acl_file_bak="/data/users.acl.bak"
retry_times=3
check_ready_times=30
retry_delay_second=2

# variables for scale out replica
current_comp_primary_node=()
current_comp_primary_fail_node=()
current_comp_other_nodes=()
other_comp_primary_nodes=()
other_comp_primary_fail_nodes=()
other_comp_other_nodes=()
network_mode="default"


init_environment(){
  if [[ -z "${CURRENT_SHARD_ADVERTISED_PORT}" ]]; then
    CURRENT_SHARD_ADVERTISED_PORT="${CURRENT_SHARD_LB_ADVERTISED_PORT}"
  fi
  if [[ -z "${CURRENT_SHARD_ADVERTISED_BUS_PORT}" ]]; then
    CURRENT_SHARD_ADVERTISED_BUS_PORT="${CURRENT_SHARD_LB_ADVERTISED_BUS_PORT}"
  fi
}

extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$CURRENT_SHARD_LB_ADVERTISED_HOST" | tr ',' '\n' ); do
    if [[ ${lb_composed_name} == *":"* ]]; then
       if [[ ${lb_composed_name%:*} == "$svc_name" ]]; then
         echo "${lb_composed_name#*:}"
         break
       fi
    else
       break
    fi
  done
}

load_redis_cluster_common_utils() {
  # the common.sh and redis-cluster-common.sh scripts are defined in the redis-cluster-scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/common.sh"
  redis_cluster_common_library_file="/scripts/redis-cluster-common.sh"
  source "${kblib_common_library_file}"
  source "${redis_cluster_common_library_file}"
}

check_and_meet_node() {
  local source_endpoint="$1"
  local source_port="$2"
  local target_endpoint="$3"
  local target_port="$4"
  local target_bus_port="$5"

  # Check for invalid port numbers and exit immediately if found
  if [ "$target_port" -eq 0 ] || [ "$target_bus_port" -eq 0 ]; then
    echo "Error: target_port ($target_port) or target_bus_port ($target_bus_port) is 0. Exiting..."
    shutdown_redis_server "$service_port"
    exit 1
  fi

  while true; do
    # Get current announce IP from the target node
    current_announce_ip=$(get_cluster_announce_ip "$target_endpoint" "$target_port")
    echo "target: $target_endpoint:$target_port, current_announce_ip: $current_announce_ip"

    # If current_announce_ip is empty, retry
    if is_empty "$current_announce_ip"; then
      echo "Error: current_announce_ip is empty"
      sleep_when_ut_mode_false 3
      continue
    fi

    # send cluster meet command to the primary node
    if send_cluster_meet_with_retry "$source_endpoint" "$source_port" "$current_announce_ip" "$target_port" "$target_bus_port"; then
      echo "Meet the node $target_endpoint successfully with new announce ip $current_announce_ip..."
      break
    else
      echo "Failed to meet the node $target_endpoint" >&2
      shutdown_redis_server "$service_port"
      exit 1
    fi
  done
}

check_and_meet_other_primary_nodes() {
  local current_primary_endpoint="$1"
  local current_primary_port="$2"
  local meet_other_comp_primary_nodes=("${other_comp_primary_nodes[@]}" "${other_comp_primary_fail_nodes[@]}")
  if [ ${#meet_other_comp_primary_nodes[@]} -eq 0 ]; then
    echo "meet_other_comp_primary_nodes is empty, skip check_and_meet_other_primary_nodes"
    return
  fi

  # node_info value format: cluster_announce_ip#pod_fqdn#endpoint:port@bus_port
  for node_info in "${meet_other_comp_primary_nodes[@]}"; do
    node_endpoint_with_port=$(echo "$node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
    node_endpoint=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $1}')
    node_port=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $2}')
    node_bus_port=$(echo "$node_info" | awk -F '@' '{print $2}')
    node_fqdn=$(echo "$node_info" | awk -F '#' '{print $2}')
    node_endpoint_for_meet="$node_endpoint"
    if [ "$network_mode" == "default" ]; then
      node_endpoint_for_meet="$node_fqdn"
    fi
    check_and_meet_node "$current_primary_endpoint" "$current_primary_port" "$node_endpoint_for_meet" "$node_port" "$node_bus_port"
    sleep_when_ut_mode_false 3
  done
}

check_and_meet_current_primary_node() {
  local primary_node_endpoint="$1"
  local primary_node_port="$2"
  local primary_bus_port="$3"

  check_and_meet_node "127.0.0.1" "$service_port" "$primary_node_endpoint" "$primary_node_port" "$primary_bus_port"
}

# get the current component nodes for scale out replica
get_current_comp_nodes_for_scale_out_replica() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  cluster_nodes_info=$(get_cluster_nodes_info "$cluster_node" "$cluster_node_port")
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info in get_current_comp_nodes_for_scale_out_replica: $cluster_nodes_info" >&2
    return 1
  fi

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  shard_count=$(echo "${ALL_SHARDS_COMPONENT_SHORT_NAMES}" | tr ',' '\n' | wc -l)
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -lt ${shard_count} ]; then
    echo "Cluster nodes info contains less than ${shard_count} nodes, returning..."
    return
  fi

  # determine network mode
  network_mode="default"
  if ! is_empty "$CURRENT_SHARD_ADVERTISED_PORT"; then
    network_mode="advertised_svc"
  elif ! is_empty "$REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT"; then
    network_mode="host_network"
  fi

  parse_node_line_info() {
    # the output of line is like:
    # 1. using the pod fqdn as the nodeAddr
    # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
    # 2. using the nodeport or lb ip as the nodeAddr
    # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:31000@31888,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
    # 3. using the host network ip as the nodeAddr
    # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:1050@1051,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
    local line="$1"

    local node_ip_port_fields
    # 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc
    node_ip_port_fields=$(echo "$line" | awk '{print $2}')

    local node_announce_ip_port
    # ip:port without bus port
    node_announce_ip_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}')

    local node_announce_ip
    node_announce_ip=$(echo "$node_announce_ip_port" | cut -d':' -f1)

    local node_port
    node_port=$(echo "$node_announce_ip_port" | cut -d':' -f2)

    local node_bus_port
    node_bus_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $2}' | awk -F ',' '{print $1}')

    local node_fqdn
    # redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local
    node_fqdn=$(echo "$line" | awk '{print $2}' | awk -F ',' '{print $2}')

    local node_role
    node_role=$(echo "$line" | awk '{print $3}')

    printf "%s %s %s %s %s" "$node_announce_ip" "$node_port" "$node_bus_port" "$node_role" "$node_fqdn"
  }

  build_node_entry() {
    local mode="$1"
    local announce_ip="$2"
    local fqdn="$3"
    local port="$4"
    local bus_port="$5"

    case "$mode" in
      "advertised_svc")
        # example format using nodeport: 172.10.0.1#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#172.10.0.1:31000@31888
        echo "$announce_ip#$fqdn#$announce_ip:$port@$bus_port"
        ;;
      "host_network")
        # example format using host network: 172.10.0.1#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#172.10.0.1:1050@1051
        echo "$announce_ip#$fqdn#$announce_ip:$port@$bus_port"
        ;;
      *)
        # example format using pod fqdn: 10.42.0.227#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc#redis-shard-sxj-0.redis-shard-sxj-headless.default.svc:6379@16379
        echo "$announce_ip#$fqdn#$fqdn:$port@$bus_port"
        ;;
    esac
  }

  # categorize node into appropriate array
  categorize_node() {
    local node_entry="$1"
    local node_role="$2"
    local belong_current_comp="$3"

    if [[ "$belong_current_comp" == "true" ]]; then
      if contains "$node_role" "master"; then
        if contains "$node_role" "fail"; then
          current_comp_primary_fail_node+=("$node_entry")
        else
          current_comp_primary_node+=("$node_entry")
        fi
      else
        current_comp_other_nodes+=("$node_entry")
      fi
    else
      if contains "$node_role" "master"; then
        if contains "$node_role" "fail"; then
          other_comp_primary_fail_nodes+=("$node_entry")
        else
          other_comp_primary_nodes+=("$node_entry")
        fi
      else
        other_comp_other_nodes+=("$node_entry")
      fi
    fi
  }

  # prepare CURRENT_SHARD_HOST_OR_PORT_LIST for advertised_svc mode
  CURRENT_SHARD_HOST_OR_PORT_LIST=()
  if [ "$network_mode" == "advertised_svc" ]; then
    IFS=',' read -ra CURRENT_POD_LIST <<< "$CURRENT_SHARD_POD_NAME_LIST"
    for pod_name in "${CURRENT_POD_LIST[@]}"; do
      svc_and_port=$(parse_advertised_svc_and_port "$pod_name" "$CURRENT_SHARD_ADVERTISED_PORT" "true")
      svc_name=${svc_and_port%:*}
      lb_host=$(extract_lb_host_by_svc_name "${svc_name}")
      if [ -n "$lb_host" ]; then
          CURRENT_SHARD_HOST_OR_PORT_LIST+=("${lb_host}:6379")
      else
          svc_port="${svc_and_port#*:}"
          CURRENT_SHARD_HOST_OR_PORT_LIST+=(":${svc_port}")
      fi
      echo "pod_name: $pod_name, svc_and_port: $svc_and_port"
    done
    # check length of CURRENT_SHARD_ANNOUNCE_IP_LIST must equal to CURRENT_POD_LIST
    if [ ${#CURRENT_SHARD_HOST_OR_PORT_LIST[@]} -ne ${#CURRENT_POD_LIST[@]} ]; then
      echo "Error: failed to get the pod ip list from KB_POD_LIST"
      return 1
    fi
  fi

  # process each node
  while read -r line; do
    local node_info
    node_info=$(parse_node_line_info "$line")
    local node_announce_ip node_fqdn node_port node_bus_port node_role
    read -r node_announce_ip node_port node_bus_port node_role node_fqdn <<< "$node_info"
    # determine if the node belongs to the current component
    belong_current_comp=false
    if [ "$network_mode" == "advertised_svc" ]; then
      for i in "${CURRENT_SHARD_HOST_OR_PORT_LIST[@]}"; do
        node_announce_info=":$node_port"
        if ! is_empty "$CURRENT_SHARD_LB_ADVERTISED_PORT"; then
          node_announce_info="$node_announce_ip:$node_port"
        fi
        if [[ "$i" == "$node_announce_info" ]]; then
          belong_current_comp=true
          break
        fi
      done
    elif [ "$network_mode" == "host_network" ]; then
      if contains "$node_port" "$SERVICE_PORT"; then
        belong_current_comp=true
      fi
    elif contains "$node_fqdn" "$CURRENT_SHARD_COMPONENT_NAME"; then
      belong_current_comp=true
    fi
    # build node entry based on network mode
    local node_entry
    node_entry=$(build_node_entry "$network_mode" "$node_announce_ip" "$node_fqdn" "$node_port" "$node_bus_port")

    # categorize nodes
    categorize_node "$node_entry" "$node_role" "$belong_current_comp"
  done <<< "$cluster_nodes_info"

  echo "current_comp_primary_node: ${current_comp_primary_node[*]}"
  echo "current_comp_primary_fail_node: ${current_comp_primary_fail_node[*]}"
  echo "current_comp_other_nodes: ${current_comp_other_nodes[*]}"
  echo "other_comp_primary_nodes: ${other_comp_primary_nodes[*]}"
  echo "other_comp_primary_fail_nodes: ${other_comp_primary_fail_nodes[*]}"
  echo "other_comp_other_nodes: ${other_comp_other_nodes[*]}"
}

# Note: During rebuild-instance, a new PVC is created without existing data and having the rebuild.flag file.
# Therefore, we must rejoin this instance to the cluster as a secondary node.
is_rebuild_instance() {
  # Early return if rebuild flag doesn't exist
  [[ ! -f /data/rebuild.flag ]] && return 1

  # Check if nodes.conf exists
  if [[ ! -f /data/nodes.conf ]]; then
    echo "Rebuild instance detected: nodes.conf missing"
    return 0
  fi

  # Check if nodes.conf contains only one node
  if [[ $(grep -c ":" /data/nodes.conf) -eq 1 ]]; then
    echo "Rebuild instance detected: single node configuration"
    return 0
  fi

  return 1
}

remove_rebuild_instance_flag() {
  if [ -f /data/rebuild.flag ]; then
    rm -f /data/rebuild.flag
    echo "remove rebuild.flag file succeeded!"
  fi
}

# scale out replica of redis cluster shard if needed
scale_redis_cluster_replica() {
  # Waiting for redis-server to start
  check_current_ready_ip="127.0.0.1"
  if [ -n "$redis_announce_host_value" ]; then
    check_current_ready_ip=$redis_announce_host_value
  fi
  if check_redis_server_ready_with_retry "127.0.0.1" "$service_port"; then
    echo "Redis server is ready, continue to scale out replica..."
  else
    echo "Redis server is not ready, exit scale out replica..." >&2
    exit 1
  fi

  if [ -f /data/nodes.conf ]; then
    echo "the nodes.conf file after redis server start:"
    cat /data/nodes.conf
  else
    echo "the nodes.conf file after redis server start is not exist"
  fi

  for target_node_name in $(echo "${CURRENT_SHARD_POD_NAME_LIST}" | tr ',' '\n'); do
     if [ -f /data/rebuild.flag ] && [ "${CURRENT_POD_NAME}" == "${target_node_name}" ]; then
       continue
     fi
     target_node_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$target_node_name")
     if is_empty "$target_node_fqdn"; then
       echo "Error: Failed to get target node fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting." >&2
       exit 1
     fi
     # get the current component nodes for scale out replica
     get_current_comp_nodes_for_scale_out_replica "$target_node_fqdn" "$service_port"
     if [ $? -eq 0 ]; then
       break
     fi
  done

  # check current_comp_primary_node is empty or not
  if [ ${#current_comp_primary_node[@]} -eq 0 ]; then
    if is_rebuild_instance; then
      echo "current instance is a rebuild-instance, the current shard primary cannot be empty, please check the cluster status" >&2
      shutdown_redis_server "$service_port"
      exit 1
    fi
    if [ ${#current_comp_primary_fail_node[@]} -eq 0 ]; then
      echo "current_comp_primary_node is empty, skip scale out replica"
      exit 0
    fi
    # if current_comp_primary_node is empty, use current_comp_primary_fail_node instead
    current_comp_primary_node=("${current_comp_primary_fail_node[@]}")
  fi

  # primary_node_info value format: cluster_announce_ip#pod_fqdn#endpoint:port@bus_port
  primary_node_info=${current_comp_primary_node[0]}
  primary_node_endpoint_with_port=$(echo "$primary_node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
  primary_node_endpoint=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $1}')
  primary_node_port=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $2}')
  primary_node_fqdn=$(echo "$primary_node_info" | awk -F '#' '{print $2}')
  primary_node_bus_port=$(echo "$primary_node_info" | awk -F '@' '{print $2}')
  primary_node_endpoint_for_meet="$primary_node_endpoint"
  if [ "$network_mode" == "default" ]; then
     primary_node_endpoint_for_meet="$primary_node_fqdn"
  fi
  if contains "$primary_node_fqdn" "$CURRENT_POD_NAME" || contains "$primary_node_info" "$current_node_host_info"; then
     echo "Current pod $CURRENT_POD_NAME is primary node, check and correct other primary nodes..."
     check_and_meet_other_primary_nodes "$primary_node_endpoint_for_meet" "$primary_node_port"
     echo "Node $CURRENT_POD_NAME is already in the cluster, skipping scale out replica..."
     exit 0
  fi
  # if the current pod is not a rebuild-instance and is already in the cluster, skip scale out replica
  if ! is_rebuild_instance && check_node_in_cluster_with_retry "$primary_node_endpoint_for_meet" "$primary_node_port" "$current_node_host_info"; then
    # if current pod is primary node, check the others primary info, if the others primary node info is expired, send cluster meet command again
    echo "Current pod $CURRENT_POD_NAME is a secondary node, check and meet current primary node..."
    check_and_meet_current_primary_node "$primary_node_endpoint_for_meet" "$primary_node_port" "$primary_node_bus_port"
    echo "Node $CURRENT_POD_NAME is already in the cluster, skipping scale out replica..."
    exit 0
  fi

  # Forget fail node when cluster is ok
  # forget_fail_node_when_cluster_is_ok "$primary_node_endpoint_for_meet" "$primary_node_port"

  # add the current node as a replica of the primary node
  primary_node_cluster_id=$(get_cluster_id_with_retry "$primary_node_endpoint_for_meet" "$primary_node_port")
  status=$?
  if is_empty "$primary_node_cluster_id" || [ $status -ne 0 ]; then
    echo "Failed to get the cluster id of the primary node $primary_node_endpoint_with_port, sleep 30s for waiting next pod to start" >&2
    sleep 30s
    shutdown_redis_server "$service_port"
    exit 1
  fi
  # current_node_with_port do not use advertised svc and port, because advertised svc and port are not ready when Pod is not Ready.
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_rebuild_instance; then
    echo "Current instance is a rebuild-instance, forget node id in the cluster firstly."
    node_id=$(get_cluster_id_with_retry "$primary_node_endpoint_for_meet" "$primary_node_port" "$current_node_host_info")
    if [ -z ${REDIS_DEFAULT_PASSWORD} ]; then
      redis-cli $REDIS_CLI_TLS_CMD -p $service_port --cluster call $primary_node_endpoint_with_port cluster forget ${node_id}
    else
      redis-cli $REDIS_CLI_TLS_CMD -p $service_port --cluster call $primary_node_endpoint_with_port cluster forget ${node_id} -a ${REDIS_DEFAULT_PASSWORD}
    fi
  fi
  current_node_with_port="$current_pod_fqdn:$service_port"
  replicated_output=$(secondary_replicated_to_primary "$current_node_with_port" "$primary_node_endpoint_with_port" "$primary_node_cluster_id")
  status=$?
  if [ $status -ne 0 ] ; then
    if is_rebuild_instance && contains "$replicated_output" "is not empty"; then
      echo "Current instance is a rebuild-instance, but the node already knows other nodes (check with CLUSTER NODES) or contains some key in database 0, shutdown redis server..." >&2
      shutdown_redis_server
      exit 1
    elif contains "$replicated_output" "is not empty"; then
      echo "Replica is not empty, Either the node already knows other nodes (check with CLUSTER NODES) or contains some key in database 0"
    elif [[ $replicated_output == *"Not all 16384 slots are covered by nodes"* ]]; then
      # shutdown the redis server if the cluster is not fully covered by nodes
      echo "Not all 16384 slots are covered by nodes, shutdown redis server" >&2
      shutdown_redis_server
      exit 1
    else
      echo "Failed to add the node $current_pod_fqdn to the cluster in scale_redis_cluster_replica, Error message: $replicated_output, shutdown redis server" >&2
      shutdown_redis_server "$service_port"
      exit 1
    fi
  fi

  if is_rebuild_instance; then
    echo "replicate the node $current_pod_fqdn to the primary node $primary_node_endpoint_with_port successfully in rebuild-instance, remove rebuild.flag file..."
    remove_rebuild_instance_flag
  fi

  # Hacky: When the entire redis cluster is restarted, a hacky sleep is used to wait for all primaries to enter the restarting state
  sleep_when_ut_mode_false 5

  # cluster meet the primary node until the current node is successfully added to the cluster
  current_primary_met=false
  declare -A other_primary_met
  for node_info in "${other_comp_primary_nodes[@]}"; do
    other_primary_met["$node_info"]=false
  done
  while true; do
    all_met=true

    # meet current component primary node if not met yet
    if ! $current_primary_met; then
      if scale_out_replica_send_meet "$primary_node_endpoint_for_meet" "$primary_node_port" "$primary_node_bus_port" "$current_node_host_info"; then
        echo "Successfully meet the primary node $primary_node_endpoint_with_port in scale_redis_cluster_replica"
        current_primary_met=true
      else
        echo "Failed to meet current primary node $primary_node_endpoint_with_port"
        all_met=false
      fi
    fi

    # meet the other components primary nodes if not met yet
    for node_info in "${other_comp_primary_nodes[@]}"; do
      if [ "${other_primary_met[$node_info]}" = false ]; then
        node_endpoint_with_port=$(echo "$node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
        node_endpoint=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $1}')
        node_port=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $2}')
        node_bus_port=$(echo "$node_info" | awk -F '@' '{print $2}')
        node_fqdn=$(echo "$node_info" | awk -F '#' '{print $2}')
        node_endpoint_for_meet="$node_endpoint"
        if [ "$network_mode" == "default" ]; then
          node_endpoint_for_meet="$node_fqdn"
        fi
        if scale_out_replica_send_meet "$node_endpoint_for_meet" "$node_port" "$node_bus_port" "$current_node_host_info"; then
          echo "Successfully meet the primary node $node_endpoint_with_port in scale_redis_cluster_replica"
          other_primary_met["$node_info"]=true
        else
          echo "Failed to meet the other component primary node $node_endpoint_with_port in scale_redis_cluster_replica" >&2
          all_met=false
        fi
      fi
    done

    # If all nodes are met successfully, break the loop
    if $all_met && $current_primary_met; then
      echo "All primary nodes have been successfully met"
      break
    fi

    sleep_when_ut_mode_false 3
  done
}

scale_out_replica_send_meet() {
  local node_endpoint_to_meet="$1"
  local node_port_to_meet="$2"
  local node_bus_port_to_meet="$3"
  local node_to_join="$4"

  if check_node_in_cluster "$node_endpoint_to_meet" "$node_port_to_meet" "$node_to_join"; then
    echo "Node $CURRENT_POD_NAME is successfully added to the cluster."
    return 0
  fi

  node_cluster_announce_ip=$(get_cluster_announce_ip_with_retry "$node_endpoint_to_meet" "$node_port_to_meet")
  # send cluster meet command to the target node
  if send_cluster_meet_with_retry "127.0.0.1" "$service_port" "$node_cluster_announce_ip" "$node_port_to_meet" "$node_bus_port_to_meet"; then
    echo "scale out replica meet the node $node_cluster_announce_ip successfully..."
  else
    echo "Failed to meet the node $node_endpoint_to_meet in scale_redis_cluster_replica, shutdown redis server" >&2
    return 1
  fi

  return 0
}

load_redis_template_conf() {
  echo "include $redis_template_conf" >> $redis_real_conf
}

build_redis_default_accounts() {
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$REDIS_REPL_PASSWORD"; then
    echo "masteruser $REDIS_REPL_USER" >> $redis_real_conf
    echo "masterauth $REDIS_REPL_PASSWORD" >> $redis_real_conf
    redis_repl_password_sha256=$(echo -n "$REDIS_REPL_PASSWORD" | sha256sum | cut -d' ' -f1)
    echo "user $REDIS_REPL_USER on +psync +replconf +ping #$redis_repl_password_sha256" >> $redis_acl_file
  fi
  if ! is_empty "$REDIS_DEFAULT_PASSWORD"; then
    echo "protected-mode yes" >> $redis_real_conf
    redis_password_sha256=$(echo -n "$REDIS_DEFAULT_PASSWORD" | sha256sum | cut -d' ' -f1)
    echo "user default on #$redis_password_sha256 ~* &* +@all " >> $redis_acl_file
  else
    echo "protected-mode no" >> $redis_real_conf
  fi
  set_xtrace_when_ut_mode_false
  echo "aclfile /data/users.acl" >> $redis_real_conf
  echo "build redis default accounts succeeded!"
}

rebuild_redis_acl_file() {
  if [ -f $redis_acl_file ]; then
    sed "/user default on/d" $redis_acl_file > $redis_acl_file_bak && mv $redis_acl_file_bak $redis_acl_file
    sed "/user $REDIS_REPL_USER on/d" $redis_acl_file > $redis_acl_file_bak && mv $redis_acl_file_bak $redis_acl_file
    sed "/user $REDIS_SENTINEL_USER on/d" $redis_acl_file > $redis_acl_file_bak && mv $redis_acl_file_bak $redis_acl_file
  else
    touch $redis_acl_file
  fi
}

build_announce_ip_and_port() {
  # build announce ip and port according to whether the advertised svc is enabled
  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value"; then
    echo "redis use advertised svc $redis_announce_host_value:$redis_announce_port_value to announce"
    {
      echo "replica-announce-port $redis_announce_port_value"
      echo "replica-announce-ip $redis_announce_host_value"
    } >> $redis_real_conf
  elif [ "$FIXED_POD_IP_ENABLED" == "true" ]; then
    echo "redis use fixed pod ip: $CURRENT_POD_IP to announce"
    echo "replica-announce-ip $CURRENT_POD_IP" >> $redis_real_conf
  else
    current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
    if is_empty "$current_pod_fqdn"; then
      echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting."
      exit 1
    fi
    echo "redis use kb pod fqdn $current_pod_fqdn to announce"
    echo "replica-announce-ip $current_pod_fqdn" >> $redis_real_conf
  fi
}

build_cluster_announce_info() {
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$CURRENT_SHARD_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_empty "$current_pod_fqdn"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from current shard pod fqdn list: $CURRENT_SHARD_POD_FQDN_LIST. Exiting."
    exit 1
  fi
  current_node_host_info="$current_pod_fqdn"
  # build announce ip and port according to whether the advertised svc is enabled
  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value" && ! is_empty "$redis_announce_bus_port_value"; then
    current_node_host_info="$redis_announce_host_value:$redis_announce_port_value"
    echo "redis cluster use advertised svc $redis_announce_host_value:$redis_announce_port_value@$redis_announce_bus_port_value to announce"
    {
      echo "cluster-announce-ip $redis_announce_host_value"
      echo "cluster-announce-bus-port $redis_announce_bus_port_value"
      # echo "cluster-announce-hostname $current_pod_fqdn"
      echo "cluster-preferred-endpoint-type ip"
      if [ "$TLS_ENABLED" == "true" ]; then
        echo "cluster-announce-tls-port $redis_announce_port_value"
        echo "cluster-announce-port 0"
      else
        echo "cluster-announce-port $redis_announce_port_value"
      fi
    } >> $redis_real_conf
  elif [ "$FIXED_POD_IP_ENABLED" == "true" ]; then
    echo "redis cluster use fixed pod ip: $CURRENT_POD_IP to announce"
    {
      echo "cluster-announce-ip $CURRENT_POD_IP"
      echo "cluster-announce-hostname $current_pod_fqdn"
      echo "cluster-preferred-endpoint-type ip"
    } >> $redis_real_conf
  else
    echo "redis cluster use pod fqdn $current_pod_fqdn to announce"
    {
      echo "cluster-announce-ip $CURRENT_POD_IP"
      echo "cluster-announce-hostname $current_pod_fqdn"
      echo "cluster-preferred-endpoint-type hostname"
    } >> $redis_real_conf
  fi
}

build_redis_cluster_service_port() {
  if ! is_empty "$SERVICE_PORT"; then
    service_port=$SERVICE_PORT
  fi
  if ! is_empty "$CLUSTER_BUS_PORT"; then
    cluster_bus_port=$CLUSTER_BUS_PORT
  fi
  if [ "$TLS_ENABLED" == "true" ]; then
    echo "tls-port $service_port" >> $redis_real_conf
  else
    echo "port $service_port" >> $redis_real_conf
  fi
  echo "cluster-port $cluster_bus_port" >> $redis_real_conf
}

parse_redis_cluster_shard_announce_addr() {
  # The value format of CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT are "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  if is_empty "$CURRENT_SHARD_ADVERTISED_PORT" || is_empty "$CURRENT_SHARD_ADVERTISED_BUS_PORT"; then
    echo "Environment variable CURRENT_SHARD_ADVERTISED_PORT and CURRENT_SHARD_ADVERTISED_BUS_PORT not found. Ignoring."
    # if redis cluster is in host network mode, use the host ip and port as the announce ip and port
    if ! is_empty "${REDIS_CLUSTER_HOST_NETWORK_PORT}" && ! is_empty "${REDIS_CLUSTER_HOST_NETWORK_BUS_PORT}"; then
      echo "redis cluster server is in host network mode, use the host ip:$CURRENT_POD_HOST_IP and port:$REDIS_CLUSTER_HOST_NETWORK_PORT, bus port:$REDIS_CLUSTER_HOST_NETWORK_BUS_PORT as the announce ip and port."
      redis_announce_port_value="$REDIS_CLUSTER_HOST_NETWORK_PORT"
      redis_announce_bus_port_value="$REDIS_CLUSTER_HOST_NETWORK_BUS_PORT"
      redis_announce_host_value="$CURRENT_POD_HOST_IP"
    fi
    return 0
  fi

  local pod_name="$CURRENT_POD_NAME"
  local port
  local bus_port
  svc_and_port=$(parse_advertised_svc_and_port "$pod_name" "$CURRENT_SHARD_ADVERTISED_PORT" "true")
  status=$?
  if [[ $status -ne 0 ]] || is_empty "$svc_and_port"; then
    echo "Exiting due to error in CURRENT_SHARD_ADVERTISED_PORT."
    exit 1
  fi

  bus_port=$(parse_advertised_svc_and_port "$pod_name" "$CURRENT_SHARD_ADVERTISED_BUS_PORT")
  status=$?
  if [[ $status -ne 0 ]] || is_empty "$bus_port"; then
    echo "Exiting due to error in CURRENT_SHARD_ADVERTISED_BUS_PORT."
    exit 1
  fi
  redis_announce_port_value="${svc_and_port#*:}"
  redis_announce_bus_port_value="$bus_port"
  svc_name=${svc_and_port%:*}
  lb_host=$(extract_lb_host_by_svc_name "${svc_name}")
  if [ -n "$lb_host" ]; then
    echo "Found load balancer host for svcName '$svc_name', value is '$lb_host'."
    redis_announce_host_value="$lb_host"
    redis_announce_port_value="6379"
    redis_announce_bus_port_value="16379"
  else
    redis_announce_host_value="$CURRENT_POD_HOST_IP"
  fi
}

start_redis_server() {
    module_path="/opt/redis-stack/lib"
    if [[ "$IS_REDIS8" == "true" ]]; then
       module_path="/usr/local/lib/redis/modules"
    fi
    exec_cmd="exec redis-server /etc/redis/redis.conf"
    if [ -f ${module_path}/redisearch.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redisearch.so ${REDISEARCH_ARGS}"
    fi
    if [ -f ${module_path}/redistimeseries.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redistimeseries.so ${REDISTIMESERIES_ARGS}"
    fi
    if [ -f ${module_path}/rejson.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/rejson.so ${REDISJSON_ARGS}"
    fi
    if [ -f ${module_path}/redisbloom.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redisbloom.so ${REDISBLOOM_ARGS}"
    fi
    if [ -f ${module_path}/redisgraph.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/redisgraph.so ${REDISGRAPH_ARGS}"
    fi
    if [ -f ${module_path}/rediscompat.so ]; then
        exec_cmd="$exec_cmd --loadmodule ${module_path}/rediscompat.so"
    fi
    # NOTE: in replication mode, load this module will lead a memory leak for slave instance.
    #if [ -f ${module_path}/redisgears.so ]; then
    #    exec_cmd="$exec_cmd --loadmodule ${module_path}/redisgears.so v8-plugin-path ${module_path}/libredisgears_v8_plugin.so ${REDISGEARS_ARGS}"
    #fi
    echo "Starting redis server cmd: $exec_cmd"
    eval "$exec_cmd"
}

# build redis cluster configuration redis.conf
build_redis_conf() {
  load_redis_template_conf
  build_redis_cluster_service_port
  build_announce_ip_and_port
  build_cluster_announce_info
  rebuild_redis_acl_file
  build_redis_default_accounts
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

init_environment
load_redis_cluster_common_utils
parse_redis_cluster_shard_announce_addr
build_redis_conf
# TODO: move to memberJoin action in the future
scale_redis_cluster_replica &
start_redis_server
