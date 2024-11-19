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
  if [ ! -f /data/sentinel/redis-sentinel.conf ]; then
    return
  fi

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

  # hack for redis sentinel when nodeport is enabled, remove known-replica line which has the same nodeport port with master
  if [ -n "$REDIS_SENTINEL_ADVERTISED_PORT" ] && [ -n "$REDIS_SENTINEL_ADVERTISED_SVC_NAME" ]; then
    temp_file=$(mktemp)
    grep "^sentinel monitor" /data/sentinel/redis-sentinel.conf > "$temp_file"

    while read -r line; do
      if [[ $line =~ ^sentinel[[:space:]]+monitor[[:space:]]+([^[:space:]]+)[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
        master_name="${BASH_REMATCH[1]}"
        master_port="${BASH_REMATCH[2]}"

        sed -i "/^sentinel known-replica ${master_name} .* ${master_port}$/d" /data/sentinel/redis-sentinel.conf
      fi
    done < "$temp_file"

    rm -f "$temp_file"
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
  echo "port $sentinel_port" >> /data/sentinel/redis-sentinel.conf
  if [ -n "$FIXED_POD_IP_ENABLED" ]; then
    echo "sentinel use the fixed pod ip to announce-ip"
    echo "sentinel announce-ip $KB_POD_IP" >> /data/sentinel/redis-sentinel.conf
  else
    kb_pod_fqdn="$KB_POD_NAME.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    {
      echo "sentinel announce-ip $kb_pod_fqdn"
      echo "sentinel resolve-hostnames yes"
      echo "sentinel announce-hostnames yes"
    } >> /data/sentinel/redis-sentinel.conf
  fi
  set +x
  if [ -n "$SENTINEL_PASSWORD" ]; then
    echo "sentinel sentinel-user $SENTINEL_USER" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel sentinel-pass $SENTINEL_PASSWORD" >> /data/sentinel/redis-sentinel.conf
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