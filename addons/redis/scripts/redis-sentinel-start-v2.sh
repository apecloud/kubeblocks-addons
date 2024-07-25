#!/bin/bash
set -ex

# Based on the Component Definition API, Redis Sentinel deployed independently

reset_redis_sentinel_conf() {
  echo "reset redis sentinel conf"
  sentinel_port=26379
  if [ -n "$SENTINEL_SERVICE_PORT" ]; then
    sentinel_port=$SENTINEL_SERVICE_PORT
  fi
  mkdir -p /data/sentinel
  if [ -f /data/sentinel/redis-sentinel.conf ]; then
    sed -i "/sentinel announce-ip/d" /data/sentinel/redis-sentinel.conf
    sed -i "/sentinel resolve-hostnames/d" /data/sentinel/redis-sentinel.conf
    sed -i "/sentinel announce-hostnames/d" /data/sentinel/redis-sentinel.conf
    set +x
    if [ -n "$SENTINEL_PASSWORD" ]; then
      sed -i "/sentinel sentinel-user/d" /data/sentinel/redis-sentinel.conf
      sed -i "/sentinel sentinel-pass/d" /data/sentinel/redis-sentinel.conf
    fi
    set -x
    sed -i "/port $sentinel_port/d" /data/sentinel/redis-sentinel.conf
  fi
}

build_redis_sentinel_conf() {
  echo "build redis sentinel conf"
  kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
  {
    echo "port $sentinel_port"
    echo "sentinel announce-ip $kb_pod_fqdn"
    echo "sentinel resolve-hostnames yes"
    echo "sentinel announce-hostnames yes"
  } >> /data/sentinel/redis-sentinel.conf
  set +x
  if [ -n "$SENTINEL_PASSWORD" ]; then
    echo "sentinel sentinel-user $SENTINEL_USER" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel sentinel-pass $SENTINEL_PASSWORD" >> /data/sentinel/redis-sentinel.conf
  fi
  set -x
  echo "build redis sentinel conf succeeded!"
}

check_register_sentinel_conf() {
  if [ -f /data/sentinel/init_done.conf ]; then
    echo "normal start"
  else
    echo "horizontal scaling"
    touch /data/sentinel/init_done.conf
    register_sentinel_conf
  fi
}

register_sentinel_conf() {

  if [[ -n "$KB_ITS_0_HOSTNAME" ]]; then
    sentinel_pod_fqdn="$KB_ITS_0_HOSTNAME"
    output=$(redis-cli -h "$sentinel_pod_fqdn" -p 26379 -a "$SENTINEL_PASSWORD" sentinel masters)
  fi

  if [ -n "$output" ]; then
    master_name=$(echo "$output" | awk '/^name$/ {getline; print}')
    master_ip=$(echo "$output" | awk '/^ip$/ {getline; print}')
    master_port=$(echo "$output" | awk '/^port$/ {getline; print}')
    echo "Master Name: $master_name, IP: $master_ip, Port: $master_port"

    echo "sentinel monitor $master_name $master_ip $master_port 2" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel down-after-milliseconds $master_name 5000" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel failover-timeout $master_name 60000" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel parallel-syncs $master_name 1" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel auth-user $master_name $REDIS_SENTINEL_USER" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel auth-pass $master_name $REDIS_SENTINEL_PASSWORD" >> /data/sentinel/redis-sentinel.conf

  else
    echo "Warning: Could not connect to Redis Sentinel or no masters found."
  fi
}

start_redis_sentinel_server() {
  echo "Starting redis sentinel server..."
  exec redis-server /data/sentinel/redis-sentinel.conf --sentinel
  echo "Start redis sentinel server succeeded!"
}

reset_redis_sentinel_conf
build_redis_sentinel_conf
check_register_sentinel_conf
start_redis_sentinel_server