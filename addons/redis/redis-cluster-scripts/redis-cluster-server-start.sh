#!/bin/bash
set -ex

load_redis_template_conf() {
  echo "include /etc/conf/redis.conf" >> /etc/redis/redis.conf
}

build_redis_default_accounts() {
  set +x
  if [ -n "$REDIS_REPL_PASSWORD" ]; then
    echo "masteruser $REDIS_REPL_USER" >> /etc/redis/redis.conf
    echo "masterauth $REDIS_REPL_PASSWORD" >> /etc/redis/redis.conf
    echo "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD" >> /data/users.acl
  fi
  if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
    echo "protected-mode yes" >> /etc/redis/redis.conf
    echo "user default on >$REDIS_DEFAULT_PASSWORD ~* &* +@all " >> /data/users.acl
  else
    echo "protected-mode no" >> /etc/redis/redis.conf
  fi
  set -x
  echo "aclfile /data/users.acl" >> /etc/redis/redis.conf
  echo "build redis default accounts succeeded!"
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
      echo "redis use immutable pod ip $KB_POD_IP to announce"
      echo "replica-announce-ip $KB_POD_IP" >> /etc/redis/redis.conf
    else
      kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
      echo "redis use kb pod fqdn $kb_pod_fqdn to announce"
      echo "replica-announce-ip $kb_pod_fqdn" >> /etc/redis/redis.conf
    fi
  fi
}

build_cluster_announce_info() {
  # build announce ip and port according to whether the advertised svc is enabled
  kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
  if [ -n "$redis_announce_host_value" ] && [ -n "$redis_announce_port_value" ] && [ -n "$redis_announce_bus_port_value" ]; then
    echo "redis cluster use advertised svc $redis_announce_host_value:$redis_announce_port_value@$redis_announce_bus_port_value to announce"
    {
      echo "cluster-announce-ip $redis_announce_host_value"
      echo "cluster-announce-port $redis_announce_port_value"
      echo "cluster-announce-bus-port $redis_announce_bus_port_value"
      echo "cluster-announce-hostname $kb_pod_fqdn"
      echo "cluster-preferred-endpoint-type ip"
    } >> /etc/redis/redis.conf
  else
    {
      echo "cluster-announce-ip $KB_POD_IP"
      echo "cluster-announce-hostname $kb_pod_fqdn"
    } >> /etc/redis/redis.conf
    if [ -n "$FIXED_POD_IP_ENABLED" ]; then
      echo "redis cluster use immutable pod ip $KB_POD_IP as preferred endpoint type"
      echo "cluster-preferred-endpoint-type ip" >> /etc/redis/redis.conf
    else
      echo "redis cluster use kb pod fqdn $kb_pod_fqdn as preferred endpoint type"
      echo "cluster-preferred-endpoint-type hostname" >> /etc/redis/redis.conf
    fi
  fi
}

build_redis_cluster_service_port() {
  service_port=6379
  cluster_bus_port=16379
  if [ -n "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
  fi
  if [ -n "$CLUSTER_BUS_PORT" ]; then
    cluster_bus_port=$CLUSTER_BUS_PORT
  fi
  {
    echo "port $service_port"
    echo "cluster-port $cluster_bus_port"
  } >> /etc/redis/redis.conf
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
  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(retry redis-cli -h "$cluster_node" -p "$cluster_node_port" cluster nodes)
  else
    cluster_nodes_info=$(retry redis-cli -h "$cluster_node" -p "$cluster_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x
  cluster_id=$(echo "$cluster_nodes_info" | grep "myself" | awk '{print $1}')
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
  local node_name="$3"

  set +x
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(retry redis-cli -h "$random_node_endpoint" -p "$random_node_port" cluster nodes)
  else
    cluster_nodes_info=$(retry redis-cli -h "$random_node_endpoint" -p "$random_node_port" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi
  set -x

  # if the cluster_nodes_info contains multiple lines and the node_name is in the cluster_nodes_info, return true
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -gt 1 ] && echo "$cluster_nodes_info" | grep -q "$node_name"; then
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

  # node_info value format: cluster_announce_ip#pod_fqdn#endpoint:port@bus_port
  for node_info in "${other_comp_primary_nodes[@]}"; do
    original_announce_ip=$(echo "$node_info" | awk -F '#' '{print $1}')
    node_endpoint_with_port=$(echo "$node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
    node_endpoint=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $1}')
    node_port=$(echo "$node_endpoint_with_port" | awk -F ':' '{print $2}')
    node_bus_port=$(echo "$node_info" | awk -F '@' '{print $2}')
    while true; do
      # random sleep 1-10 seconds
      wait_random_second 10 1
      current_announce_ip=$(get_cluster_announce_ip "$node_endpoint" "$node_port")
      echo "original_announce_ip: $original_announce_ip, node_endpoint_with_port: $node_endpoint_with_port, current_announce_ip: $current_announce_ip"
      # if current_announce_ip is empty, we need to retry
      if [ -z "$current_announce_ip" ]; then
        wait_random_second 3 1
        echo "current_announce_ip is empty, retry..."
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
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -eq 1 ]; then
    echo "Cluster nodes info contains only one line, returning..."
    return
  fi

  # if the $REDIS_CLUSTER_ADVERTISED_PORT is set, parse the advertised ports
  # the value format of $REDIS_CLUSTER_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  declare -A advertised_ports
  local using_advertised_ports=false
  # Parse host network ports if redis cluster is in host network mode
  declare -A host_network_ports
  local using_host_network=false
  if [ -n "$REDIS_CLUSTER_ADVERTISED_PORT" ]; then
    using_advertised_ports=true
    IFS=',' read -ra ADDR <<< "$REDIS_CLUSTER_ADVERTISED_PORT"
    for i in "${ADDR[@]}"; do
      port=$(echo $i | cut -d':' -f2)
      advertised_ports[$port]=1
    done
  elif [ -n "$REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT" ] && [ -n "$HOST_NETWORK_ENABLED" ]; then
    using_host_network=true
    IFS=',' read -ra port_mappings <<< "$REDIS_CLUSTER_ALL_SHARDS_HOST_NETWORK_PORT"
    for mapping in "${port_mappings[@]}"; do
      shard_name=$(echo "$mapping" | cut -d':' -f1)
      mapping_port=$(echo "$mapping" | cut -d':' -f2)
      host_network_ports["$shard_name"]=$mapping_port
    done
  fi

  # the output of line is like:
  # 1. using the pod fqdn as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 10.42.0.227:6379@16379,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # 2. using the nodeport or lb ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:31000@31888,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  # 3. using the host network ip as the nodeAddr
  # 4958e6dca033cd1b321922508553fab869a29d 172.10.0.1:1050@1051,redis-shard-sxj-0.redis-shard-sxj-headless.default.svc.cluster.local master - 0 1711958289570 4 connected 0-1364 5461-6826 10923-12287
  while read -r line; do
    node_ip_port_fields=$(echo "$line" | awk '{print $2}')
    node_announce_ip_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}')
    node_bus_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $2}' | awk -F ',' '{print $1}')
    node_announce_ip=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f1)
    node_port=$(echo "$node_ip_port_fields" | awk -F '@' '{print $1}' | cut -d':' -f2)
    node_fqdn=$(echo "$line" | awk '{print $2}' | awk -F ',' '{print $2}')
    node_role=$(echo "$line" | awk '{print $3}')

    local final_port=$SERVICE_PORT
    if $using_host_network; then
      for shard_name in "${!host_network_ports[@]}"; do
        if echo "$node_fqdn" | grep -q "$shard_name"; then
          final_port=${host_network_ports["$shard_name"]}
          break
        fi
      done
    fi

    if $using_advertised_ports; then
      if [[ ${advertised_ports[$node_port]+_} ]]; then
        if [[ "$node_role" =~ "master" ]]; then
          current_comp_primary_node+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        else
          current_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        fi
      else
        if [[ "$node_role" =~ "master" ]]; then
          other_comp_primary_nodes+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        else
          other_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_announce_ip_port@$node_bus_port")
        fi
      fi
    else
      if [[ "$node_fqdn" =~ "$KB_CLUSTER_COMP_NAME"* ]]; then
        if [[ "$node_role" =~ "master" ]]; then
          current_comp_primary_node+=("$node_announce_ip#$node_fqdn#$node_fqdn:$final_port@$node_bus_port")
        else
          current_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_fqdn:$final_port@$node_bus_port")
        fi
      else
        if [[ "$node_role" =~ "master" ]]; then
          other_comp_primary_nodes+=("$node_announce_ip#$node_fqdn#$node_fqdn:$final_port@$node_bus_port")
        else
          other_comp_other_nodes+=("$node_announce_ip#$node_fqdn#$node_fqdn:$final_port@$node_bus_port")
        fi
      fi
    fi
  done <<< "$cluster_nodes_info"

  echo "current_comp_primary_node: ${current_comp_primary_node[*]}"
  echo "current_comp_other_nodes: ${current_comp_other_nodes[*]}"
  echo "other_comp_primary_nodes: ${other_comp_primary_nodes[*]}"
  echo "other_comp_other_nodes: ${other_comp_other_nodes[*]}"
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

  current_pod_name=$KB_POD_NAME
  current_pod_fqdn="$current_pod_name.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
  # check if exists KB_LEADER env, if exists, it means that is scale out replica
  if [ -n "$KB_LEADER" ]; then
    target_node_fqdn="$KB_LEADER.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
  else
    # if not exists KB_LEADER env, try to get the redis cluster info from pod which index=0
    pod_name_prefix=$(extract_pod_name_prefix "$current_pod_name")
    target_node_fqdn="$pod_name_prefix-0.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
  fi

  # get the current component nodes for scale out replica
  get_current_comp_nodes_for_scale_out_replica "$target_node_fqdn" "$service_port"

  # check current_comp_primary_node is empty or not
  if [ ${#current_comp_primary_node[@]} -eq 0 ]; then
    echo "current_comp_primary_node is empty, skip scale out replica"
    exit 0
  fi

  # primary_node_info value format: cluster_announce_ip#pod_fqdn#endpoint:port@bus_port
  primary_node_info=${current_comp_primary_node[0]}
  primary_node_endpoint_with_port=$(echo "$primary_node_info" | awk -F '@' '{print $1}' | awk -F '#' '{print $3}')
  primary_node_endpoint=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $1}')
  primary_node_port=$(echo "$primary_node_endpoint_with_port" | awk -F ':' '{print $2}')
  primary_node_fqdn=$(echo "$primary_node_info" | awk -F '#' '{print $2}')
  primary_node_bus_port=$(echo "$primary_node_info" | awk -F '@' '{print $2}')
  if is_node_in_cluster "$primary_node_endpoint" "$primary_node_port" "$current_pod_name"; then
    current_pod_with_svc="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME"
    if [[ $primary_node_fqdn == *"$current_pod_with_svc"* ]]; then
      echo "Current pod $current_pod_name is primary node, check and correct other primary nodes..."
      check_and_correct_other_primary_nodes "$primary_node_endpoint" "$primary_node_port"
    fi
    echo "Node $current_pod_name is already in the cluster, skipping scale out replica..."
    exit 0
  fi

  # add the current node as a replica of the primary node
  primary_node_cluster_id=$(get_cluster_id "$primary_node_endpoint" "$primary_node_port")
  if [ -z "$primary_node_cluster_id" ]; then
    echo "Failed to get the cluster id of the primary node $primary_node_endpoint_with_port"
    shutdown_redis_server
    exit 1
  fi
  # current_node_with_port do not use advertised svc and port, because advertised svc and port are not ready when Pod is not Ready.
  current_node_with_port="$current_pod_fqdn:$service_port"
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
    if [[ $replicated_output == *"is not empty"* ]]; then
      echo "Replica is not empty, Either the node already knows other nodes (check with CLUSTER NODES) or contains some key in database 0"
      break
    else
      echo "Failed to add the node $current_pod_fqdn to the cluster in scale_redis_cluster_replica"
      echo "Error message: $replicated_output"
    fi
    attempt=$((attempt + 1))
    sleep 1
  done

  if [ $attempt -gt $max_attempts ]; then
    echo "Failed to add the node to cluster after $attempt attempts, abort and shutdown redis server"
    shutdown_redis_server
    exit 1
  fi

  # cluster meet the primary node until the current node is successfully added to the cluster
  while true; do
    if is_node_in_cluster "$primary_node_endpoint" "$primary_node_port" "$current_pod_name"; then
      echo "Node $current_pod_name is successfully added to the cluster."
      break
    fi
    primary_node_cluster_announce_ip=$(get_cluster_announce_ip "$primary_node_endpoint" "$primary_node_port")
    # send cluster meet command to the primary node
    set +ex
    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
      meet_command="redis-cli -p $service_port cluster meet $primary_node_cluster_announce_ip $primary_node_port $primary_node_bus_port"
      logging_mask_meet_command="$meet_command"
    else
      meet_command="redis-cli -a $REDIS_DEFAULT_PASSWORD -p $service_port cluster meet $primary_node_cluster_announce_ip $primary_node_port $primary_node_bus_port"
      logging_mask_meet_command="${meet_command/$REDIS_DEFAULT_PASSWORD/********}"
    fi
    echo "scale out replica meet command: $logging_mask_meet_command"
    if ! $meet_command
    then
        echo "Failed to meet the node $primary_node_endpoint_with_port in scale_redis_cluster_replica, shutdown redis server"
        shutdown_redis_server
        exit 1
    fi
    set -ex
    sleep 3
  done
  exit 0
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
  port=$(parse_advertised_port "$pod_name" "${REDIS_CLUSTER_ADVERTISED_PORT}")
  if [[ $? -ne 0 ]] || [[ -z "$port" ]]; then
    echo "Exiting due to error in REDIS_CLUSTER_ADVERTISED_PORT."
    exit 1
  fi
  redis_announce_port_value="$port"
  redis_announce_host_value="$KB_HOST_IP"

  if [[ -n "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" ]]; then
    port=$(parse_advertised_port "$pod_name" "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}")
    if [[ $? -ne 0 ]] || [[ -z "$port" ]]; then
      echo "Exiting due to error in REDIS_CLUSTER_ADVERTISED_BUS_PORT."
      exit 1
    fi
    redis_announce_bus_port_value="$port"
  fi
}

rebuild_redis_acl_file() {
  if [ -f /data/users.acl ]; then
    sed -i "/user default on/d" /data/users.acl
    sed -i "/user $REDIS_REPL_USER on/d" /data/users.acl
    sed -i "/user $REDIS_SENTINEL_USER on/d" /data/users.acl
  else
    touch /data/users.acl
  fi
}

start_redis_server() {
    exec_cmd="exec redis-server /etc/redis/redis.conf"
    if [ -f /opt/redis-stack/lib/redisearch.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisearch.so ${REDISEARCH_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/redistimeseries.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redistimeseries.so ${REDISTIMESERIES_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/rejson.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/rejson.so ${REDISJSON_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/redisbloom.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisbloom.so ${REDISBLOOM_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/redisgraph.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisgraph.so ${REDISGRAPH_ARGS}"
    fi
    if [ -f /opt/redis-stack/lib/rediscompat.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/rediscompat.so"
    fi
    if [ -f /opt/redis-stack/lib/redisgears.so ]; then
        exec_cmd="$exec_cmd --loadmodule /opt/redis-stack/lib/redisgears.so v8-plugin-path /opt/redis-stack/lib/libredisgears_v8_plugin.so ${REDISGEARS_ARGS}"
    fi
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

parse_redis_cluster_announce_addr "$KB_POD_NAME"
build_redis_conf
scale_redis_cluster_replica &
start_redis_server
