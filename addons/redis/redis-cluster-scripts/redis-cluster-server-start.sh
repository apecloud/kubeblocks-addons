#!/bin/sh
set -ex

load_redis_template_conf() {
  echo "include /etc/conf/redis.conf" >> /etc/redis/redis.conf
}

build_redis_default_accounts() {
  set +x
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
  set -x
  echo "aclfile /data/users.acl" >> /etc/redis/redis.conf
  echo "build redis cluster default accounts succeeded!"
}

build_announce_ip_and_port() {
    kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
    echo "redis use kb pod fqdn $kb_pod_fqdn to announce"
    echo "replica-announce-ip $kb_pod_fqdn" >> /etc/redis/redis.conf
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

rebuild_redis_acl_file() {
  {{- $data_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
  if [ -f /data/users.acl ]; then
    sed -i "/user default on/d" /data/users.acl
    sed -i "/user $REDIS_REPL_USER on/d" /data/users.acl
    sed -i "/user $REDIS_SENTINEL_USER on/d" /data/users.acl
  else
    touch /data/users.acl
  fi
}

extract_ordinal_from_pod_name() {
  local pod_name="$1"
  local ordinal="${pod_name##*-}"
  echo "$ordinal"
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
  rebuild_redis_acl_file
  build_redis_default_accounts
}

build_redis_conf
# TODO: if the redis cluster has been initialized, it should be added as secondary replica to corresponding primary node
start_redis_server
