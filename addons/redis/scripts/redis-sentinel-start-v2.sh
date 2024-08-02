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

recover_registered_redis_servers_if_needed() {
  if [ -f /data/sentinel/init_done.conf ]; then
    echo "normal start"
  else
    echo "horizontal scaling"
    if recover_registered_redis_servers; then
      touch /data/sentinel/init_done.conf
    else
      echo "recover_registered_redis_servers failed"
      exit 1
    fi
  fi
}

recover_registered_redis_servers() {
    if [[ -n "${SENTINEL_POD_FQDN_LIST}" ]]; then
        old_ifs="$IFS"
        IFS=','
        set -f
        read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
        set +f
        IFS="$old_ifs"

        output=""
        for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
          if [ -n "$SENTINEL_PASSWORD" ]; then
            temp_output=$(redis-cli -h "$sentinel_pod_fqdn" -p 26379 -a "$SENTINEL_PASSWORD" sentinel masters 2>/dev/null || true)
          else
            temp_output=$(redis-cli -h "$sentinel_pod_fqdn" -p 26379 sentinel masters 2>/dev/null || true)
          fi
          if [[ -n "$temp_output" ]]; then
              output="$temp_output"
              break
          fi
        done
    else
        echo "SENTINEL_POD_FQDN_LIST environment variable is not set or empty."
        return 1
    fi
    #TODO:Check if the sentinel has been deleted before, as adding a new sentinel might read the past configuration, leading to conflicts with the current setup.
    if [[ -n "$output" ]]; then
        master_name=""
        master_ip=""
        master_port=""
        master_down_after_milliseconds=""
        master_quorum=""
        master_failover_timeout=""
        master_parallel_syncs=""
        while read -r line; do
            case "$line" in
                name)
                    read -r master_name
                    ;;
                ip)
                    read -r master_ip
                    ;;
                port)
                    read -r master_port
                    ;;
                down-after-milliseconds)
                    read -r master_down_after_milliseconds
                    ;;
                quorum)
                    read -r master_quorum
                    ;;
                failover-timeout)
                    read -r master_failover_timeout
                    ;;
                parallel-syncs)
                    read -r master_parallel_syncs
                    ;;
            esac

            if [[ -n "$master_name" && -n "$master_ip" && -n "$master_port" && \
                  -n "$master_down_after_milliseconds" && -n "$master_failover_timeout" && \
                  -n "$master_parallel_syncs" && -n "$master_quorum" ]]; then
            echo "Master Name: $master_name, IP: $master_ip, Port: $master_port, \
            down-after-milliseconds: $master_down_after_milliseconds, \
            failover-timeout: $master_failover_timeout, \
            parallel-syncs: $master_parallel_syncs, quorum: $master_quorum"

            echo "sentinel monitor $master_name $master_ip $master_port $master_quorum" >> /data/sentinel/redis-sentinel.conf
            echo "sentinel down-after-milliseconds $master_name $master_down_after_milliseconds" >> /data/sentinel/redis-sentinel.conf
            echo "sentinel failover-timeout $master_name $master_failover_timeout" >> /data/sentinel/redis-sentinel.conf
            echo "sentinel parallel-syncs $master_name $master_parallel_syncs" >> /data/sentinel/redis-sentinel.conf
            echo "sentinel auth-user $master_name $REDIS_SENTINEL_USER" >> /data/sentinel/redis-sentinel.conf
            cluster_name="$KB_CLUSTER_NAME"
            comp_name="${master_name#"$cluster_name"-}"
            comp_name_upper=$(echo "$comp_name" | tr '[:lower:]' '[:upper:]')
            set +x
            if [[ -v REDIS_SENTINEL_PASSWORD ]]; then
                var_name="REDIS_SENTINEL_PASSWORD_${comp_name_upper}"
                if [[ -n "${!var_name}" ]]; then
                  auth_pass="${!var_name}"
                else
                  auth_pass="$REDIS_SENTINEL_PASSWORD"
                fi
                echo "sentinel auth-pass $master_name $auth_pass" >> /data/sentinel/redis-sentinel.conf
            else
                echo "REDIS_SENTINEL_PASSWORD is not set"
                return 1
            fi
            set -x
            sleep 30
            master_name=""
            master_ip=""
            master_port=""
            master_down_after_milliseconds=""
            master_quorum=""
            master_failover_timeout=""
            master_parallel_syncs=""
            fi
        done <<< "$output"
    else
        echo "Initialization in progress, or unable to connect to Redis Sentinel, or no master nodes found."
    fi
}

start_redis_sentinel_server() {
  echo "Starting redis sentinel server..."
  exec redis-server /data/sentinel/redis-sentinel.conf --sentinel
  echo "Start redis sentinel server succeeded!"
}

reset_redis_sentinel_conf
build_redis_sentinel_conf
recover_registered_redis_servers_if_needed
start_redis_sentinel_server