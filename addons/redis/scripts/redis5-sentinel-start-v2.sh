#!/bin/bash

set -ex

# Based on the Component Definition API, Redis Sentinel deployed independently

extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$REDIS_SENTINEL_ADVERTISED_LB_HOST" | tr ',' '\n' ); do
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

parse_redis_sentinel_announce_addr() {
  local pod_name="$1"
  if [[ -z "${REDIS_SENTINEL_ADVERTISED_PORT}" ]]; then
     REDIS_SENTINEL_ADVERTISED_PORT="$REDIS_SENTINEL_LB_ADVERTISED_PORT"
  fi
  # try to get the announce ip and port from REDIS_ADVERTISED_PORT(support NodePort currently) first
  if [[ -z "${REDIS_SENTINEL_ADVERTISED_PORT}" ]]; then
    echo "Environment variable REDIS_SENTINEL_ADVERTISED_PORT not found. Ignoring."
    # if redis sentinel is in host network mode, use the host ip and port as the announce ip and port
    if [[ -n "${REDIS_SENTINEL_HOST_NETWORK_PORT}" ]] && [[ -n "$HOST_NETWORK_ENABLED" ]]; then
      echo "redis sentinel is in host network mode, use the host ip:$KB_HOST_IP and port:$REDIS_SENTINEL_HOST_NETWORK_PORT as the announce ip and port."
      redis_sentinel_announce_port_value="$REDIS_SENTINEL_HOST_NETWORK_PORT"
      redis_sentinel_announce_host_value="$KB_HOST_IP"
    fi
    return 0
  fi

  # the value format of REDIS_SENTINEL_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  IFS=',' read -ra advertised_ports <<< "${REDIS_SENTINEL_ADVERTISED_PORT}"

  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  for advertised_port in "${advertised_ports[@]}"; do
    IFS=':' read -ra parts <<< "$advertised_port"
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_SENTINEL_ADVERTISED_PORT: $REDIS_SENTINEL_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_sentinel_announce_port_value="$port"
      lb_host=$(extract_lb_host_by_svc_name "$svc_name")
      if [ -n "$lb_host" ]; then
        echo "Found load balancer host for svcName '$svc_name', value is '$lb_host'."
        redis_sentinel_announce_host_value="$lb_host"
        redis_sentinel_announce_port_value="26379"
      else
        redis_sentinel_announce_host_value="$KB_HOST_IP"
      fi
      found=true
      break
    fi
  done

  if [[ "$found" == false ]]; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_SENTINEL_ADVERTISED_PORT: $REDIS_SENTINEL_ADVERTISED_PORT. Exiting."
    exit 1
  fi
}

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
  sed -i "/sentinel announce-port/d" /data/sentinel/redis-sentinel.conf

  set +x
  if [ -n "$SENTINEL_PASSWORD" ]; then
    sed -i "/requirepass/d" /data/sentinel/redis-sentinel.conf
  fi
  set -x

  sed -i "/port $sentinel_port/d" /data/sentinel/redis-sentinel.conf

  # hack for redis sentinel when nodeport is enabled, remove known-replica line which has the same nodeport port with master
  if [ -n "$REDIS_SENTINEL_ADVERTISED_PORT" ]; then
    temp_file=$(mktemp)
    grep "^sentinel monitor" /data/sentinel/redis-sentinel.conf > "$temp_file"

    while read -r line; do
      if [[ $line =~ ^sentinel[[:space:]]+monitor[[:space:]]+([^[:space:]]+)[[:space:]]+[^[:space:]]+[[:space:]]+([^[:space:]]+) ]]; then
        master_name="${BASH_REMATCH[1]}"
        master_port="${BASH_REMATCH[2]}"

        sed -i "/^sentinel known-replica ${master_name} .* ${master_port}$/d" /data/sentinel/redis-sentinel.conf
        sed -i "/^sentinel known-sentinel ${master_name}/d" /data/sentinel/redis-sentinel.conf
      fi
    done < "$temp_file"

    rm -f "$temp_file"
  fi
}

build_redis_sentinel_conf() {
  echo "build redis sentinel conf"
  echo "port $sentinel_port" >> /data/sentinel/redis-sentinel.conf
  # build announce ip and port according to whether the announce addr is exist
  if [ -n "$redis_sentinel_announce_port_value" ] && [ -n "$redis_sentinel_announce_host_value" ]; then
    echo "redis sentinel use announce addr $redis_sentinel_announce_host_value:$redis_sentinel_announce_port_value to announce"
    echo "sentinel announce-ip $redis_sentinel_announce_host_value" >> /data/sentinel/redis-sentinel.conf
    echo "sentinel announce-port $redis_sentinel_announce_port_value" >> /data/sentinel/redis-sentinel.conf
  else
    if [ -n "$FIXED_POD_IP_ENABLED" ]; then
      echo "sentinel use the fixed pod ip to announce-ip"
      echo "sentinel announce-ip $KB_POD_IP" >> /data/sentinel/redis-sentinel.conf
    else
      echo "sentinel use the pod ip to announce-ip"
      echo "sentinel announce-ip $KB_POD_IP" >> /data/sentinel/redis-sentinel.conf
    fi
  fi
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

parse_redis_sentinel_announce_addr "$KB_POD_NAME"
reset_redis_sentinel_conf
build_redis_sentinel_conf
start_redis_sentinel_server