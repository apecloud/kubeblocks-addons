#!/bin/sh
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
    set +x
    if [ -n "$SENTINEL_PASSWORD" ]; then
        sed -i "/requirepass/d" /data/sentinel/redis-sentinel.conf
    fi
    set -x
    sed -i "/port $sentinel_port/d" /data/sentinel/redis-sentinel.conf
  fi
}

build_redis_sentinel_conf() {
  echo "build redis sentinel conf"
  kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc"
  kb_pod_ip=""
  while [ -z "$kb_pod_ip" ]; do
    kb_pod_ip=$(getent hosts "$kb_pod_fqdn" | awk '{ print $1 }')
    if [ -z "$kb_pod_ip" ]; then
      echo "Waiting for Sentinel to be available..."
      sleep 2
    fi
  done

  echo "Found Sentinel IP: $kb_pod_ip"
  {
    echo "port $sentinel_port"
    echo "sentinel announce-ip $kb_pod_ip"
  } >> /data/sentinel/redis-sentinel.conf
  set +x
  if [ -n "$SENTINEL_PASSWORD" ]; then
    echo "requirepass $SENTINEL_PASSWORD" >> /data/sentinel/redis-sentinel.conf
  fi
  set -x
  echo "build redis sentinel conf succeeded!"
}

start_redis_sentinel_server() {
  echo "Starting redis sentinel server..."
  exec redis-server /data/sentinel/redis-sentinel.conf --sentinel
  echo "Start redis sentinel server succeeded!"
}

reset_redis_sentinel_conf
build_redis_sentinel_conf
start_redis_sentinel_server