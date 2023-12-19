#!/bin/sh
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
  if [ ! -z "$REDIS_SENTINEL_PASSWORD" ]; then
    echo "user $REDIS_SENTINEL_USER on allchannels +multi +slaveof +ping +exec +subscribe +config|rewrite +role +publish +info +client|setname +client|kill +script|kill >$REDIS_SENTINEL_PASSWORD" >> /data/users.acl
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
  # build announce ip and port according to whether the NodePort is enabled
  if [ -n "$redis_node_port_host_value" ] && [ -n "$redis_node_port_value" ]; then
      echo "redis use nodeport $redis_node_port_host_value:$redis_node_port_value to announce"
      echo "replica-announce-port $redis_node_port_value" >> /etc/redis/redis.conf
      echo "replica-announce-ip $redis_node_port_host_value.$KB_NAMESPACE" >> /etc/redis/redis.conf
  else
    echo "redis use kb pod fqdn $KB_POD_FQDN to announce"
    echo "replica-announce-ip $KB_POD_FQDN" >> /etc/redis/redis.conf
  fi
}

build_redis_service_port() {
  service_port=6379
  if [ ! -z "$SERVICE_PORT" ]; then
    service_port=$SERVICE_PORT
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

start_redis_server() {
    exec redis-server /etc/redis/redis.conf \
    --loadmodule /opt/redis-stack/lib/redisearch.so ${REDISEARCH_ARGS} \
    --loadmodule /opt/redis-stack/lib/redisgraph.so ${REDISGRAPH_ARGS} \
    --loadmodule /opt/redis-stack/lib/redistimeseries.so ${REDISTIMESERIES_ARGS} \
    --loadmodule /opt/redis-stack/lib/rejson.so ${REDISJSON_ARGS} \
    --loadmodule /opt/redis-stack/lib/redisbloom.so ${REDISBLOOM_ARGS}
}

create_replication() {
    # Waiting for redis-server to start
    if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
      retry redis-cli -h 127.0.0.1 -p $service_port -a "$REDIS_DEFAULT_PASSWORD" ping
    else
      retry redis-cli -h 127.0.0.1 -p $service_port ping
    fi

    # Waiting for primary pod information from the DownwardAPI annotation to be available
    attempt=1
    max_attempts=20
    while [ $attempt -le $max_attempts ] && [ -z "$(cat /kb-podinfo/primary-pod)" ]; do
      echo "Waiting for primary pod information from the DownwardAPI annotation to be available, attempt $attempt of $max_attempts..."
      sleep 5
      attempt=$((attempt + 1))
    done
    primary=$(cat /kb-podinfo/primary-pod)
    echo "DownwardAPI get primary=$primary" >> /etc/redis/.kb_set_up.log
    echo "KB_POD_NAME=$KB_POD_NAME" >> /etc/redis/.kb_set_up.log
    if [ -z "$primary" ]; then
      echo "Primary pod information not available. shutdown redis-server..."
      if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
        redis-cli -h 127.0.0.1 -p $service_port -a "$REDIS_DEFAULT_PASSWORD" shutdown
      else
        redis-cli -h 127.0.0.1 -p $service_port shutdown
      fi
      exit 1
    fi

    # create a replication relationship, if failed, shutdown redis-server
    if [ "$primary" = "$KB_POD_NAME" ]; then
      echo "primary instance skip create a replication relationship."
    else
      primary_fqdn="$primary.$KB_CLUSTER_NAME-$KB_COMP_NAME-headless.$KB_NAMESPACE.svc"
      echo "primary_fqdn=$primary_fqdn" >> /etc/redis/.kb_set_up.log
      echo "wait for primary:$primary_fqdn redis-server to start"
      if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
        # wait for primary redis-server to start
        until redis-cli -h $primary_fqdn -p $service_port -a "$REDIS_DEFAULT_PASSWORD" ping; do sleep 2; done
        echo "start to create a replication relationship"
        redis-cli -h 127.0.0.1 -p $service_port -a "$REDIS_DEFAULT_PASSWORD" replicaof $primary_fqdn $service_port
      else
        until redis-cli -h $primary_fqdn -p $service_port ping; do sleep 2; done
        echo "start to create a replication relationship"
        redis-cli -h 127.0.0.1 -p $service_port replicaof $primary_fqdn $service_port
      fi
      if [ $? -ne 0 ]; then
        echo "Failed to create a replication relationship. shutdown redis-server..."
        if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
          redis-cli -h 127.0.0.1 -p $service_port -a "$REDIS_DEFAULT_PASSWORD" shutdown
        else
          redis-cli -h 127.0.0.1 -p $service_port shutdown
        fi
      fi
      echo "create a replication relationship succeeded."
    fi
}

pod_ordinal=$(extract_ordinal_from_pod_name $KB_POD_NAME)
gen_redis_node_port="REDIS_NODE_PORT_${pod_ordinal}"
gen_redis_node_port_host="REDIS_NODE_PORT_SVC_NAME_${pod_ordinal}"
eval redis_node_port_value="\$$gen_redis_node_port"
eval redis_node_port_host_value="\$$gen_redis_node_port_host"
echo "redis_node_port_value=$redis_node_port_value, redis_node_port_host_value=$redis_node_port_host_value"

# build redis.conf
build_redis_conf() {
  load_redis_template_conf
  build_announce_ip_and_port
  build_redis_service_port
  rebuild_redis_acl_file
  build_redis_default_accounts
}

build_redis_conf
create_replication &
start_redis_server
