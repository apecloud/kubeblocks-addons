#!/bin/bash
set -ex

load_redis_template_conf() {
  echo "include /etc/conf/redis.conf" >> /etc/redis/redis.conf
}

build_redis_default_accounts() {
  set +x
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    {
      echo "protected-mode yes"
      echo "requirepass $REDIS_DEFAULT_PASSWORD"
      echo "masterauth $REDIS_DEFAULT_PASSWORD"
    } >> /etc/redis/redis.conf
  else
    echo "protected-mode no" >> /etc/redis/redis.conf
  fi
  set -x
  echo "build default accounts succeeded!"
}

build_announce_ip_and_port() {
  # build announce ip and port according to whether the advertised svc is enabled
  if [ -n "$redis_announce_host_value" ] && [ -n "$redis_announce_port_value" ]; then
    echo "redis use advertised svc $redis_announce_host_value:$redis_announce_port_value to announce"
    {
      echo "replica-announce-port $redis_announce_port_value"
      echo "replica-announce-ip $redis_announce_host_value"
    } >> /etc/redis/redis.conf
  else
    if [ -n "$FIXED_POD_IP_ENABLED" ]; then
      echo "redis use fixed pod ip $KB_POD_IP to announce"
      echo "replica-announce-ip $KB_POD_IP" >> /etc/redis/redis.conf
    else
      # only above v6.2.x sentinel has optional support for host names.
      # https://redis.io/docs/latest/operate/oss_and_stack/management/sentinel/#ip-addresses-and-dns-names
      echo "redis use pod ip $KB_POD_IP to announce"
      echo "replica-announce-ip $KB_POD_IP" >> /etc/redis/redis.conf
    fi
  fi
}

build_cluster_announce_info() {
  # redis v6.x does not support cluster-announce-hostname and cluster-preferred-endpoint-type configs
  if [ -n "$redis_announce_host_value" ] && [ -n "$redis_announce_port_value" ] && [ -n "$redis_announce_bus_port_value" ]; then
    echo "redis cluster use advertised svc $redis_announce_host_value:$redis_announce_port_value@$redis_announce_bus_port_value to announce"
    {
      echo "cluster-announce-ip $redis_announce_host_value"
      echo "cluster-announce-port $redis_announce_port_value"
      echo "cluster-announce-bus-port $redis_announce_bus_port_value"
    } >> /etc/redis/redis.conf
  else
    echo "redis cluster use pod ip $KB_POD_IP to announce"
    echo "cluster-announce-ip $KB_POD_IP" >> /etc/redis/redis.conf
  fi
}

build_redis_cluster_service_port() {
  # redis v6.x does not support cluster-port configuration
  service_port=6379
  if [ -n "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
  fi
  echo "port $service_port" >> /etc/redis/redis.conf
}

shutdown_redis_server() {
  set +x
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    redis-cli -h 127.0.0.1 -p "$service_port" -a "$REDIS_DEFAULT_PASSWORD" shutdown
  else
    redis-cli -h 127.0.0.1 -p "$service_port" shutdown
  fi
  set -x
  echo "shutdown redis server succeeded!"
}

# usage: retry <command>
retry() {
  local max_attempts=20
  local attempt=1
  set +x
  until "$@" || [ $attempt -eq $max_attempts ]; do
    echo "Command failed. Attempt $attempt of $max_attempts. Retrying in 5 seconds..."
    attempt=$((attempt + 1))
    sleep 3
  done
  set -x
  if [ $attempt -eq $max_attempts ]; then
    echo "Command failed after $max_attempts attempts. shutdown redis-server..."
    shutdown_redis_server
  fi
}

extract_pod_name_prefix() {
  local pod_name="$1"
  # shellcheck disable=SC2001
  prefix=$(echo "$pod_name" | sed 's/-[0-9]\+$//')
  echo "$prefix"
}

wait_random_second() {
  local max_time="$1"
  local min_time="$2"
  local random_time=$((RANDOM % (max_time - min_time + 1) + min_time))
  echo "Sleeping for $random_time seconds"
  sleep "$random_time"
}

get_cluster_id() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  local pod_fqdn="$3"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(retry redis-cli -h "$cluster_node" -p "$cluster_node_port" cluster nodes)
  else
    cluster_nodes_info=$(retry redis-cli -h "$cluster_node" -p "$cluster_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x
  if [ -n "${pod_fqdn}" ]; then
    cluster_id=$(echo "$cluster_nodes_info" | grep "${pod_fqdn}" | awk '{print $1}')
  else
    cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
  fi
  echo "$cluster_id"
}

get_cluster_announce_ip() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(retry redis-cli -h "$cluster_node" -p "$cluster_node_port" cluster nodes)
  else
    cluster_nodes_info=$(retry redis-cli -h "$cluster_node" -p "$cluster_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x
  cluster_announce_ip=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $2}' | awk -F ':' '{print $1}')
  echo "$cluster_announce_ip"
}

is_node_in_cluster() {
  local random_node_endpoint="$1"
  local random_node_port="$2"
  local node_ip="$3"

  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(retry redis-cli -h "$random_node_endpoint" -p "$random_node_port" cluster nodes)
  else
    cluster_nodes_info=$(retry redis-cli -h "$random_node_endpoint" -p "$random_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x

  # if the cluster_nodes_info contains multiple lines and the node_ip is in the cluster_nodes_info, return true
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -gt 1 ] && echo "$cluster_nodes_info" | grep -q "$node_ip:"; then
    true
  else
    false
  fi
}

check_and_correct_other_primary_nodes() {
  local current_primary_endpoint="$1"
  local current_primary_port="$2"

  if [ ${#other_comp_primary_nodes[@]} -eq 0 ]; then
    echo "other_comp_primary_nodes is empty, skip check_and_correct_other_primary_nodes"
    return
  fi

  # node_info value format: cluster_announce_ip#endpoint:port@bus_port
  for node_info in "${other_comp_primary_nodes[@]}"; do
    original_announce_ip=$(echo "$node_info" | awk -F '#' '{print $1}')
    node_endpoint_with_port=$(echo "$node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $2}')
    node_endpoint=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $1}')
    node_port=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $2}')
    node_bus_port=$(echo "$node_info" | awk -F '@' '{print $2}')
    while true; do
      # random sleep 1-10 seconds
      wait_random_second 10 1
      current_announce_ip=$(get_cluster_announce_ip "$node_endpoint" "$node_port")
      echo "original_announce_ip: $original_announce_ip, node_endpoint_with_port: $node_endpoint_with_port, current_announce_ip: $current_announce_ip"
      # if current_announce_ip is empty, retry it
      if [ -z "$current_announce_ip" ]; then
          echo "Error: current_announce_ip is empty"
          wait_random_second 3 1
          continue
      fi

      if [ "$node_port" -eq 0 ] || [ "$node_bus_port" -eq 0 ]; then
          echo "Error: node_port or node_bus_port is 0"
          wait_random_second 3 1
          continue
      fi

      # if original_announce_ip not equal to current_announce_ip, we need to correct it with the current_announce_ip
      if [ "$original_announce_ip" != "$current_announce_ip" ]; then
        # send cluster meet command to the primary node
        set +x
        if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
          meet_command="redis-cli -h $current_primary_endpoint -p $current_primary_port cluster meet $current_announce_ip $node_port $node_bus_port"
          logging_mask_meet_command="$meet_command"
        else
          meet_command="redis-cli -h $current_primary_endpoint -p $current_primary_port -a $REDIS_DEFAULT_PASSWORD cluster meet $current_announce_ip $node_port $node_bus_port"
          logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
        fi
        echo "check and correct other primary nodes meet command: $logging_mask_meet_command"
        if ! $meet_command
        then
            echo "Failed to meet the node $node_endpoint_with_port in check_and_correct_other_primary_nodes"
            shutdown_redis_server
            exit 1
        else
          echo "Meet the node $node_endpoint_with_port successfully with new announce ip $current_announce_ip..."
          break
        fi
        set -x
      else
        echo "node_info $node_info is correct, skipping..."
        break
      fi
    done
  done
}

# get the current component nodes for scale out replica
get_current_comp_nodes_for_scale_out_replica() {
  local cluster_node="$1"
  local cluster_node_port="$2"
  local max_retries=10
  local retry_interval=3

  get_cluster_nodes_with_retry() {
    local attempt=1
    local result=""

    while [ $attempt -le $max_retries ]; do
      set +x
      if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
        result=$(redis-cli -h "$cluster_node" -p "$cluster_node_port" cluster nodes)
      else
        result=$(redis-cli -h "$cluster_node" -p "$cluster_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
      fi
      if [ $? -eq 0 ] && [ -n "$result" ]; then
        echo "$result"
        return 0
      fi
      set -x

      echo "Attempt $attempt failed. Error: $result. Retrying in $retry_interval seconds..." >&2
      sleep $retry_interval
      attempt=$((attempt + 1))
    done

    echo "Failed to execute redis-cli command after $max_retries attempts"
    return 1
  }

  cluster_nodes_info=$(get_cluster_nodes_with_retry)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to get cluster nodes info"
    return 1
  fi

  current_comp_primary_node=()
  current_comp_other_nodes=()
  other_comp_primary_nodes=()
  other_comp_other_nodes=()

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  shard_count=$(echo "${REDIS_CLUSTER_ALL_SHARDS}" | tr ',' '\n' | wc -l)
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -lt ${shard_count} ]; then
    echo "Cluster nodes info contains less than ${shard_count} nodes, returning..."
    return
  fi

  # get current pod ip list from KB_POD_LIST
  IFS=',' read -ra CURRENT_POD_LIST <<< "$KB_POD_LIST"
  CURRENT_POD_IP_LIST=()
  for pod_name in "${CURRENT_POD_LIST[@]}"; do
    local pod_fqdn="$pod_name.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    pod_mapping_ip=$(getent hosts "$pod_fqdn" | awk '{ print $1 }')
    echo "pod_name: $pod_name, pod_fqdn: $pod_fqdn, pod_mapping_ip: $pod_mapping_ip"
    CURRENT_POD_IP_LIST+=("$pod_mapping_ip")
  done
  # check length of CURRENT_POD_IP_LIST must equal to CURRENT_POD_LIST
  if [ ${#CURRENT_POD_IP_LIST[@]} -ne ${#CURRENT_POD_LIST[@]} ]; then
    echo "Error: failed to get the pod ip list from KB_POD_LIST"
    return 1
  fi

  # the output of line is like:
  # 1. using the fixed pod ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379 master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  while read -r line; do
    node_ip_port_fields=$(echo "$line" | awk '{print $2}')
    node_announce_ip_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}')
    node_bus_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $2}' | awk -F ',' '{print $1}')
    node_announce_ip=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f1)
    node_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f2)
    node_role=$(echo "$line" | awk '{print $3}')

    belong_current_comp=false
    for i in "${CURRENT_POD_IP_LIST[@]}"; do
      if [[ "$i" = "$node_announce_ip" ]]; then
        belong_current_comp=true
      fi
    done

    if $belong_current_comp; then
      if [[ "$node_role" =~ "master" && ! "$node_role" =~ "fail" ]]; then
        current_comp_primary_node+=("$node_announce_ip#$node_announce_ip_port@$node_bus_port")
      else
        current_comp_other_nodes+=("$node_announce_ip#$node_announce_ip_port@$node_bus_port")
      fi
    else
      if [[ "$node_role" =~ "master" && ! "$node_role" =~ "fail" ]]; then
        other_comp_primary_nodes+=("$node_announce_ip#$node_announce_ip_port@$node_bus_port")
      else
        other_comp_other_nodes+=("$node_announce_ip#$node_announce_ip_port@$node_bus_port")
      fi
    fi
  done <<< "$cluster_nodes_info"

  echo "current_comp_primary_node: ${current_comp_primary_node[*]}"
  echo "current_comp_other_nodes: ${current_comp_other_nodes[*]}"
  echo "other_comp_primary_nodes: ${other_comp_primary_nodes[*]}"
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
  set +x
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    retry redis-cli -h 127.0.0.1 -p "$service_port" -a "$REDIS_DEFAULT_PASSWORD" ping
  else
    # compatible with the old version without password which advertised svc is not supported
    retry redis-cli -h 127.0.0.1 -p "$service_port" ping
  fi
  set -x

  if [ -f /data/nodes.conf ]; then
    echo "the nodes.conf file after redis server start:"
    cat /data/nodes.conf
  else
    echo "the nodes.conf file after redis server start is not exist"
  fi

  current_pod_name=$KB_POD_NAME
  current_pod_ip=$KB_POD_IP
  current_pod_fqdn="$current_pod_name.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
  # get the current component nodes for scale out replica
  pod_name_prefix=$(extract_pod_name_prefix "$current_pod_name")
  for ((i=0; i < $KB_COMP_REPLICAS; i++))
  do
     target_node_fqdn="$pod_name_prefix-${i}.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
     if [ -f /data/rebuild.flag ] && [ "${KB_POD_NAME}" == "$pod_name_prefix-${i}" ]; then
       continue
     fi
     get_current_comp_nodes_for_scale_out_replica "$target_node_fqdn" "$service_port"
     if [ $? -eq 0 ]; then
       break
     fi
  done

  # check current_comp_primary_node is empty or not
  if [ ${#current_comp_primary_node[@]} -eq 0 ]; then
    if is_rebuild_instance; then
      echo "current instance is a rebuild-instance, the current shard primary cannot be empty, please check the cluster status"
      shutdown_redis_server
      exit 1
    fi
    echo "current_comp_primary_node is empty, skip scale out replica"
    exit 0
  fi

  # primary_node_info value format: cluster_announce_ip#endpoint:port@bus_port
  primary_node_info=${current_comp_primary_node[0]}
  primary_node_endpoint_with_port=$(echo "$primary_node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $2}')
  primary_node_endpoint=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $1}')
  primary_node_port=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $2}')
  primary_node_bus_port=$(echo "$primary_node_info" | awk -F '@' '{print $2}')
  # if the current pod is not a rebuild-instance and is already in the cluster, skip scale out replica
  if ! is_rebuild_instance && is_node_in_cluster "$primary_node_endpoint" "$primary_node_port" "$current_pod_ip"; then
    if [[ $primary_node_endpoint == "$KB_POD_IP" ]]; then
      echo "Current pod $current_pod_name is primary node, check and correct other primary nodes..."
      check_and_correct_other_primary_nodes "$primary_node_endpoint" "$primary_node_port"
    fi
    echo "Node $current_pod_name is already in the cluster, skipping scale out replica..."
    exit 0
  fi

  # add the current node as a replica of the primary node
  primary_node_cluster_id=$(get_cluster_id "$primary_node_endpoint" "$primary_node_port")
  if [ -z "$primary_node_cluster_id" ]; then
    echo "Failed to get the cluster id of the primary node $primary_node_endpoint_with_port, sleep 30s for waiting next pod to start"
    sleep 30
    shutdown_redis_server
    exit 1
  fi
  if is_rebuild_instance; then
    echo "Current instance is a rebuild-instance, forget node id in the cluster firstly."
    node_id=$(get_cluster_id "$primary_node_endpoint" "$primary_node_port" "$current_pod_fqdn")
    if [ -z ${REDIS_DEFAULT_PASSWORD} ]; then
      redis-cli -p $service_port --cluster call $primary_node_endpoint_with_port cluster forget ${node_id}
    else
      redis-cli -p $service_port --cluster call $primary_node_endpoint_with_port cluster forget ${node_id} -a ${REDIS_DEFAULT_PASSWORD}
    fi
  fi
  current_node_with_port="$current_pod_ip:$service_port"
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    replicated_command="redis-cli --cluster add-node $current_node_with_port $primary_node_endpoint_with_port --cluster-slave --cluster-master-id $primary_node_cluster_id -p $service_port"
    logging_mask_replicated_command="$replicated_command"
  else
    replicated_command="redis-cli --cluster add-node $current_node_with_port $primary_node_endpoint_with_port --cluster-slave --cluster-master-id $primary_node_cluster_id -a $REDIS_DEFAULT_PASSWORD -p $service_port"
    logging_mask_replicated_command="${replicated_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "scale out replica replicated command: $logging_mask_replicated_command"
  set -x
  # Keep trying until add-node is done.
  # And the current_pod_fqdn DNS cache time is normally 30 seconds, thus make 30 attempts
  local max_attempts=30
  local attempt=1

  while [ $attempt -le $max_attempts ]
  do
    # Avoid exiting with non-zero code and avoid printing password
    set +ex
    replicated_output=$($replicated_command)
    replicated_exit_code=$?
    set -ex
    echo "Attempt $attempt: Scale out replica replicated command result: $replicated_output"
    if [ $replicated_exit_code -eq 0 ]; then
      break
    fi
    if is_rebuild_instance && [[ $replicated_output == *"is not empty"* ]]; then
      echo "Current instance is a rebuild-instance, but the node already knows other nodes (check with CLUSTER NODES) or contains some key in database 0, shutdown redis server..."
      shutdown_redis_server
    elif [[ $replicated_output == *"is not empty"* ]]; then
      echo "Replica is not empty, Either the node already knows other nodes (check with CLUSTER NODES) or contains some key in database 0"
      break
    elif [[ $replicated_output == *"Not all 16384 slots are covered by nodes"* ]]; then
      # shutdown the redis server if the cluster is not fully covered by nodes
      echo "Not all 16384 slots are covered by nodes, shutdown redis server"
      shutdown_redis_server
    else
      echo "Failed to add the node $current_pod_fqdn to the cluster in scale_redis_cluster_replica"
      echo "Error message: $replicated_output"
    fi
    attempt=$((attempt + 1))
    sleep 5
  done

  if [ $attempt -gt $max_attempts ]; then
    echo "Failed to add the node to cluster after $attempt attempts, abort and shutdown redis server"
    shutdown_redis_server
    exit 1
  fi

  if is_rebuild_instance; then
    echo "replicate the node $current_pod_fqdn to the primary node $primary_node_endpoint_with_port successfully in rebuild-instance, remove rebuild.flag file..."
    remove_rebuild_instance_flag
  fi

  # Hacky: When the entire redis cluster is restarted, a hacky sleep is used to wait for all primaries to enter the restarting state
  sleep 5

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
      if scale_out_replica_send_meet "$primary_node_endpoint" "$primary_node_port" "$primary_node_bus_port" "$current_pod_ip"; then
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
        node_endpoint_with_port=$(echo "$node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $2}')
        node_endpoint=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $1}')
        node_port=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $2}')
        node_bus_port=$(echo "$node_info" | awk -F '@' '{print $2}')

        if scale_out_replica_send_meet "$node_endpoint" "$node_port" "$node_bus_port" "$current_pod_ip"; then
          echo "Successfully meet the primary node $node_endpoint_with_port in scale_redis_cluster_replica"
          other_primary_met["$node_info"]=true
        else
          echo "Failed to meet the other component primary node $node_endpoint_with_port in scale_redis_cluster_replica"
          all_met=false
        fi
      fi
    done

    # If all nodes are met successfully, break the loop
    if $all_met && $current_primary_met; then
      echo "All primary nodes have been successfully met"
      break
    fi

    sleep 3
  done
  exit 0
}

scale_out_replica_send_meet() {
  local node_endpoint_to_meet="$1"
  local node_port_to_meet="$2"
  local node_bus_port_to_meet="$3"
  local node_to_join="$4"
  if is_node_in_cluster "$node_endpoint_to_meet" "$node_port_to_meet" "$node_to_join"; then
    echo "Node $current_pod_name is successfully added to the cluster."
    return 0
  fi
  node_cluster_announce_ip=$(get_cluster_announce_ip "$node_endpoint_to_meet" "$node_port_to_meet")
  # send cluster meet command to the primary node
  set +ex
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    meet_command="redis-cli -p $service_port cluster meet $node_cluster_announce_ip $node_port_to_meet $node_bus_port_to_meet"
    logging_mask_meet_command="$meet_command"
  else
    meet_command="redis-cli -a $REDIS_DEFAULT_PASSWORD -p $service_port cluster meet $node_cluster_announce_ip $node_port_to_meet $node_bus_port_to_meet"
    logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
  fi
  echo "scale out replica meet command: $logging_mask_meet_command"
  if ! $meet_command
  then
    echo "Failed to meet the node $node_endpoint_to_meet in scale_out_replica_send_meet, shutdown redis server"
    shutdown_redis_server
    exit 1
  fi
  set -ex
  return 1
}

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$REDIS_ADVERTISED_LB_HOST" | tr ',' '\n' ); do
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


parse_advertised_svc_and_port() {
  local pod_name="$1"
  local advertised_ports="$2"
  local only_port=$3
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
      if [[ "${only_port}" == "true" ]]; then
         echo "$port"
      else
         echo "$svc_name:$port"
      fi
      found=true
      return 0
    fi
  done

  if [[ "$found" == false ]]; then
    return 1
  fi
}

parse_redis_cluster_announce_addr() {
  local pod_name="$1"

  # The value format of REDIS_CLUSTER_ADVERTISED_PORT and REDIS_CLUSTER_ADVERTISED_BUS_PORT are "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  if [[ -z "${REDIS_CLUSTER_ADVERTISED_PORT}" ]] || [[ -z "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" ]]; then
    echo "Environment variable REDIS_CLUSTER_ADVERTISED_PORT and REDIS_CLUSTER_ADVERTISED_BUS_PORT not found. Ignoring."
    # if redis cluster is in host network mode, use the host ip and port as the announce ip and port
    if [[ -n "${REDIS_CLUSTER_HOST_NETWORK_PORT}" ]] && [[ -n "${REDIS_CLUSTER_HOST_NETWORK_BUS_PORT}" ]] && [[ -n "$HOST_NETWORK_ENABLED" ]]; then
      echo "redis cluster server is in host network mode, use the host ip:$KB_HOST_IP and port:$REDIS_CLUSTER_HOST_NETWORK_PORT, bus port:$REDIS_CLUSTER_HOST_NETWORK_BUS_PORT as the announce ip and port."
      redis_announce_port_value="$REDIS_CLUSTER_HOST_NETWORK_PORT"
      redis_announce_bus_port_value="$REDIS_CLUSTER_HOST_NETWORK_BUS_PORT"
      redis_announce_host_value="$KB_HOST_IP"
    fi
    return 0
  fi

  local port
  svc_and_port=$(parse_advertised_svc_and_port "$pod_name" "${REDIS_CLUSTER_ADVERTISED_PORT}")
  if [[ $? -ne 0 ]] || [[ -z "$svc_and_port" ]]; then
    echo "Exiting due to error in REDIS_CLUSTER_ADVERTISED_PORT."
    exit 1
  fi
  if [[ -n "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" ]]; then
    port=$(parse_advertised_svc_and_port "$pod_name" "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" "true")
    if [[ $? -ne 0 ]] || [[ -z "$port" ]]; then
      echo "Exiting due to error in REDIS_CLUSTER_ADVERTISED_BUS_PORT."
      exit 1
    fi
    redis_announce_bus_port_value="$port"
  fi
  redis_announce_port_value="${svc_and_port#*:}"
  svc_name=${svc_and_port%:*}
  lb_host=$(extract_lb_host_by_svc_name "${svc_name}")
  if [ -n "$lb_host" ]; then
    echo "Found load balancer host for svcName '$svc_name', value is '$lb_host'."
    redis_announce_host_value="$lb_host"
    redis_announce_port_value="6379"
    redis_announce_bus_port_value="16379"
  else
    redis_announce_host_value="$KB_HOST_IP"
  fi
}

start_redis_server() {
  exec_cmd="exec redis-server /etc/redis/redis.conf"
  echo "Starting redis server cmd: $exec_cmd"
  eval "$exec_cmd"
}

# build redis cluster configuration redis.conf
build_redis_conf() {
  load_redis_template_conf
  build_redis_cluster_service_port
  build_announce_ip_and_port
  build_cluster_announce_info
  build_redis_default_accounts
}

init_environment(){
  if [[ -z "${REDIS_CLUSTER_ADVERTISED_PORT}" ]]; then
    REDIS_CLUSTER_ADVERTISED_PORT="${REDIS_CLUSTER_LB_ADVERTISED_PORT}"
  fi
  if [[ -z "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" ]]; then
    REDIS_CLUSTER_ADVERTISED_BUS_PORT="${REDIS_CLUSTER_LB_ADVERTISED_BUS_PORT}"
  fi
}

init_environment
parse_redis_cluster_announce_addr "$KB_POD_NAME"
build_redis_conf
scale_redis_cluster_replica &
start_redis_server
