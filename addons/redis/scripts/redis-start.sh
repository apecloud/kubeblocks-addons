#!/bin/bash
set -ex

declare -g primary
declare -g default_initialize_pod_ordinal=0
declare -g headless_postfix="headless"

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

load_redis_template_conf() {
  echo "include /etc/conf/redis.conf" >> /etc/redis/redis.conf
}

build_redis_default_accounts() {
  if [ -n "$REDIS_REPL_PASSWORD" ]; then
    echo "masteruser $REDIS_REPL_USER" >> /etc/redis/redis.conf
    echo "masterauth $REDIS_REPL_PASSWORD" >> /etc/redis/redis.conf
    echo "user $REDIS_REPL_USER on +psync +replconf +ping >$REDIS_REPL_PASSWORD" >> /data/users.acl
  fi
  if [ -n "$REDIS_SENTINEL_PASSWORD" ]; then
    echo "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill >$REDIS_SENTINEL_PASSWORD" >> /data/users.acl
  fi
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
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
    echo "redis use nodeport $redis_advertised_svc_host_value:$redis_advertised_svc_port_value to announce"
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

build_redis_service_port() {
  service_port=6379
  if [ -n "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
  fi
  echo "port $service_port" >> /etc/redis/redis.conf
}

build_replicaof_config() {
  init_or_get_primary_node
  if [ "$primary" = "$KB_POD_NAME" ]; then
    echo "primary instance skip create a replication relationship."
  else
    primary_fqdn="$primary.$KB_CLUSTER_COMP_NAME-$headless_postfix.$KB_NAMESPACE.svc"
    echo "replicaof $primary_fqdn $service_port" >> /etc/redis/redis.conf
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

init_or_get_primary_node() {
  # TODO: if redis sentinel exist, try to get primary node from redis sentinel

  # if KB_LEADER is not empty, use KB_LEADER as primary node.
  if [ -n "$KB_LEADER" ]; then
    echo "KB_LEADER is not empty, use KB_LEADER:$KB_LEADER as primary node."
    primary="$KB_LEADER"
  else
    # if KB_LEADER is empty, it may be the first time to initialize the cluster or there is currently no primary node in the cluster due to various reasons.
    echo "KB_LEADER is empty, use default initialize pod_ordinal:$default_initialize_pod_ordinal as primary node."
    primary="$KB_CLUSTER_COMP_NAME-$default_initialize_pod_ordinal"
  fi

  if [ "$primary" = "$KB_POD_NAME" ]; then
    echo "current pod is primary node, skip check role in kernel"
    return
  fi

  # check the primary is real master role or not
  local primary_fqdn="$primary.$KB_CLUSTER_COMP_NAME-$headless_postfix.$KB_NAMESPACE.svc"
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    check_kernel_role_cmd="redis-cli -h $primary_fqdn -p $service_port -a $REDIS_DEFAULT_PASSWORD info replication | grep 'role:' | awk -F: '{print \$2}'"
  else
    check_kernel_role_cmd="redis-cli -h $primary_fqdn -p $service_port info replication | grep 'role:' | awk -F: '{print \$2}'"
  fi
  retry_times=10
  while true; do
    check_role=$(eval "$check_kernel_role_cmd")
    if [[ "$check_role" =~ "master" ]]; then
      break
    else
      echo "the selected primary node is not the real master in kernel, existing primary node: $primary, role: $check_role"
    fi
    sleep 3
    retry_times=$((retry_times - 1))
    if [ $retry_times -eq 0 ]; then
      echo "check primary node role failed after 20 times, existing primary node: $primary, role: $check_role"
      exit 1
    fi
  done
}

start_redis_server() {
    exec redis-server /etc/redis/redis.conf \
    --loadmodule /opt/redis-stack/lib/redisearch.so ${REDISEARCH_ARGS} \
    --loadmodule /opt/redis-stack/lib/redisgraph.so ${REDISGRAPH_ARGS} \
    --loadmodule /opt/redis-stack/lib/redistimeseries.so ${REDISTIMESERIES_ARGS} \
    --loadmodule /opt/redis-stack/lib/rejson.so ${REDISJSON_ARGS} \
    --loadmodule /opt/redis-stack/lib/redisbloom.so ${REDISBLOOM_ARGS}
}

parse_redis_advertised_svc_if_exist() {
  local pod_name="$1"

  if [[ -z "${REDIS_ADVERTISED_PORT}" ]]; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  IFS=',' read -ra advertised_ports <<< "${REDIS_ADVERTISED_PORT}"

  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  for advertised_port in "${advertised_ports[@]}"; do
    IFS=':' read -ra parts <<< "$advertised_port"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_advertised_svc_port_value="$port"
      redis_advertised_svc_host_value="$KB_HOST_IP"
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting."
    exit 1
  fi
}

# build redis.conf
build_redis_conf() {
  load_redis_template_conf
  build_announce_ip_and_port
  build_redis_service_port
  build_replicaof_config
  rebuild_redis_acl_file
  build_redis_default_accounts
}

parse_redis_advertised_svc_if_exist "$KB_POD_NAME"
build_redis_conf
start_redis_server
