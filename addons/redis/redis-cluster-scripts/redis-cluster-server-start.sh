#!/bin/bash
set -ex

load_redis_template_conf() {
  echo "include /etc/conf/redis.conf" >> /etc/redis/redis.conf
}

build_redis_default_accounts() {
  if [ ! -z "$REDIS_REPL_PASSWORD" ]; then
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
  echo "aclfile /data/users.acl" >> /etc/redis/redis.conf
}

build_announce_ip_and_port() {
  # build announce ip and port according to whether the advertised svc is enabled
  if [ -n "$redis_advertised_svc_host_value" ] && [ -n "$redis_advertised_svc_port_value" ]; then
    echo "redis use advertised svc $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
    {
      echo "replica-announce-port $redis_advertised_svc_port_value"
      echo "replica-announce-ip $redis_advertised_svc_host_value"
    } >> /etc/redis/redis.conf
  else
    kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
    echo "redis use kb pod fqdn $kb_pod_fqdn to announce"
    echo "replica-announce-ip $kb_pod_fqdn" >> /etc/redis/redis.conf
  fi
}

build_cluster_announce_info() {
  # build announce ip and port according to whether the advertised svc is enabled
  kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
  if [ -n "$redis_advertised_svc_host_value" ] && [ -n "$redis_advertised_svc_port_value" ] && [ -n "$redis_advertised_svc_bus_port_value" ]; then
    echo "redis cluster use advertised svc $redis_advertised_svc_host_value:$redis_advertised_svc_port_value@$redis_advertised_svc_bus_port_value to announce"
    {
      # TODO: config set cluster-announce-ip/cluster-announce-port/cluster-announce-bus-port in postProvision lifecycleAction after redis cluster is created
      echo "cluster-announce-hostname $kb_pod_fqdn"
      echo "cluster-preferred-endpoint-type ip"
    } >> /etc/redis/redis.conf
  else
    echo "redis use kb pod fqdn $kb_pod_fqdn to announce"
    {
      echo "cluster-announce-hostname $kb_pod_fqdn"
      echo "cluster-preferred-endpoint-type hostname"
    } >> /etc/redis/redis.conf
  fi
}

build_redis_cluster_service_port() {
  service_port=6379
  cluster_bus_port=16379
  if [ ! -z "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
    cluster_bus_port=$((service_port+10000))
  fi
  echo "port $service_port" >> /etc/redis/redis.conf
}

# usage: retry <command>
retry() {
  local max_attempts=20
  local attempt=1
  until "$@" || [ $attempt -eq $max_attempts ]; do
    echo "Command '$*' failed. Attempt $attempt of $max_attempts. Retrying in 5 seconds..."
    attempt=$((attempt + 1))
    sleep 3
  done
  if [ $attempt -eq $max_attempts ]; then
    echo "Command '$*' failed after $max_attempts attempts. shutdown redis-server..."
    if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
      redis-cli -h 127.0.0.1 -p $service_port -a "$REDIS_DEFAULT_PASSWORD" shutdown
    else
      redis-cli -h 127.0.0.1 -p $service_port shutdown
    fi
  fi
}

extract_pod_name_prefix() {
  local pod_name="$1"
  # shellcheck disable=SC2001
  prefix=$(echo "$pod_name" | sed 's/-[0-9]\+$//')
  echo "$prefix"
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

is_node_in_cluster() {
  local random_node_fqdn="$1"
  local node_name="$2"

  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$random_node_fqdn" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$random_node_fqdn" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi

  # if the cluster_nodes_info contains multiple lines and the node_name is in the cluster_nodes_info, return true
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -gt 1 ] && echo "$cluster_nodes_info" | grep -q "$node_name"; then
    true
  else
    false
  fi
}

# get the current component nodes for scale out replica
get_current_comp_nodes_for_scale_out_replica() {
  local cluster_node="$1"
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$SERVICE_PORT" cluster nodes)
  else
    cluster_nodes_info=$(redis-cli -h "$cluster_node" -p "$SERVICE_PORT" -a "$REDIS_DEFAULT_PASSWORD" cluster nodes)
  fi

  current_comp_primary_node=()
  current_comp_other_nodes=()

  # if the cluster_nodes_info contains only one line, it means that the cluster not be initialized
  if [ "$(echo "$cluster_nodes_info" | wc -l)" -eq 1 ]; then
    echo "Cluster nodes info contains only one line, returning..."
    return
  fi

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

# scale out replica of redis cluster shard if needed
scale_redis_cluster_replica() {

  # Waiting for redis-server to start
  if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
    retry redis-cli -h 127.0.0.1 -p $SERVICE_PORT -a "$REDIS_DEFAULT_PASSWORD" ping
  else
    retry redis-cli -h 127.0.0.1 -p $SERVICE_PORT ping
  fi

  current_pod_name=$KB_POD_NAME
  current_pod_fqdn="$current_pod_name.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
  # check if exists KB_LEADER env, if exists, it means that is scale out replica
  if [ -n "$KB_LEADER" ]; then
    target_node_fqdn="$KB_LEADER.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
  else
    # if not exists KB_LEADER env, try to get the redis cluster info from pod which index=0
    pod_name_prefix=$(extract_pod_name_prefix "$current_pod_name")
    target_node_fqdn="$pod_name_prefix-0.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
  fi
  target_node_with_port="$target_node_fqdn:$SERVICE_PORT"

  # get the current component nodes for scale out replica
  get_current_comp_nodes_for_scale_out_replica "$target_node_fqdn"

  # check current_comp_primary_node is empty or not
  if [ ${#current_comp_primary_node[@]} -eq 0 ]; then
    echo "current_comp_primary_node is empty, skip scale out replica"
    exit 0
  fi

  # check if the current node is already in the cluster
  primary_node_with_port=${current_comp_primary_node[0]}
  primary_node_fqdn=$(echo "$primary_node_with_port" | awk -F ':' '{print $1}')
  if is_node_in_cluster "$primary_node_fqdn" "$current_pod_name"; then
    echo "Node $current_pod_name is already in the cluster, skipping..."
    exit 0
  fi

  # add the current node as a replica of the primary node
  primary_node_cluster_id=$(get_cluster_id "$primary_node_fqdn")
  if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
    replicated_command="redis-cli --cluster add-node $current_pod_fqdn:$SERVICE_PORT $primary_node_with_port --cluster-slave --cluster-master-id $primary_node_cluster_id"
  else
    replicated_command="redis-cli --cluster add-node $current_pod_fqdn:$SERVICE_PORT $primary_node_with_port --cluster-slave --cluster-master-id $primary_node_cluster_id -a $REDIS_DEFAULT_PASSWORD"
  fi
  echo "Scale out replica replicated command: $replicated_command"
  if ! $replicated_command
  then
      echo "Failed to add the node $current_pod_fqdn to the cluster in scale_redis_cluster_replica"
      if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
        redis-cli -h 127.0.0.1 -p $service_port -a "$REDIS_DEFAULT_PASSWORD" shutdown
      else
        redis-cli -h 127.0.0.1 -p $service_port shutdown
      fi
      exit 1
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

parse_redis_cluster_advertised_svc_if_exist() {
  local pod_name="$1"

  # The value format of REDIS_CLUSTER_ADVERTISED_PORT and REDIS_CLUSTER_ADVERTISED_BUS_PORT are "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  if [[ -z "${REDIS_CLUSTER_ADVERTISED_PORT}" ]] || [[ -z "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" ]]; then
    echo "Environment variable REDIS_CLUSTER_ADVERTISED_PORT and REDIS_CLUSTER_ADVERTISED_BUS_PORT not found. Ignoring."
    return 0
  fi

  local port
  port=$(parse_advertised_port "$pod_name" "${REDIS_CLUSTER_ADVERTISED_PORT}")
  if [[ $? -ne 0 ]] || [[ -z "$port" ]]; then
    echo "Exiting due to error in REDIS_CLUSTER_ADVERTISED_PORT."
    exit 1
  fi
  redis_advertised_svc_port_value="$port"
  redis_advertised_svc_host_value="$KB_HOST_IP"

  if [[ -n "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}" ]]; then
    port=$(parse_advertised_port "$pod_name" "${REDIS_CLUSTER_ADVERTISED_BUS_PORT}")
    if [[ $? -ne 0 ]] || [[ -z "$port" ]]; then
      echo "Exiting due to error in REDIS_CLUSTER_ADVERTISED_BUS_PORT."
      exit 1
    fi
    redis_advertised_svc_bus_port_value="$port"
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
    exec redis-server /etc/redis/redis.conf \
    --loadmodule /opt/redis-stack/lib/redisearch.so ${REDISEARCH_ARGS} \
    --loadmodule /opt/redis-stack/lib/redisgraph.so ${REDISGRAPH_ARGS} \
    --loadmodule /opt/redis-stack/lib/redistimeseries.so ${REDISTIMESERIES_ARGS} \
    --loadmodule /opt/redis-stack/lib/rejson.so ${REDISJSON_ARGS} \
    --loadmodule /opt/redis-stack/lib/redisbloom.so ${REDISBLOOM_ARGS}
}

# build redis cluster configuration redis.conf
build_redis_conf() {
  load_redis_template_conf
  build_announce_ip_and_port
  build_cluster_announce_info
  rebuild_redis_acl_file
  build_redis_default_accounts
}

parse_redis_cluster_advertised_svc_if_exist "$KB_POD_NAME"
build_redis_conf
scale_redis_cluster_replica &
start_redis_server
