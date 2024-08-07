#!/bin/bash
set -ex

# Based on the Component Definition API, Redis Sentinel deployed independently
check_redis_sentinel_member_leave_status() {
  if [ -f /data/sentinel/member_leave.conf ]; then
    echo "sentinel is performing a member leave operation and will not continue to start"
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

reset_redis_sentinel_monitor_conf() {
    echo "reset sentinel monitor configuration file if there are any residual configurations "
    if [ -f /data/sentinel/redis-sentinel.conf ]; then
      sed -i "/sentinel monitor/d" /data/sentinel/redis-sentinel.conf
      sed -i "/sentinel sentinel down-after-milliseconds/d" /data/sentinel/redis-sentinel.conf
      sed -i "/sentinel failover-timeout/d" /data/sentinel/redis-sentinel.conf
      sed -i "/sentinel parallel-syncs/d" /data/sentinel/redis-sentinel.conf
      set +x
      if [[ -v REDIS_SENTINEL_PASSWORD ]]; then
        sed -i "/sentinel auth-user/d" /data/sentinel/redis-sentinel.conf
        sed -i "/sentinel auth-pass/d" /data/sentinel/redis-sentinel.conf
      fi
      set -x
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
        local max_retries=5
        local retry_count=0
        local success=false
        for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
          while [ $retry_count -lt $max_retries ]; do
            if [ -n "$SENTINEL_PASSWORD" ]; then
              temp_output=$(redis-cli -h "$sentinel_pod_fqdn" -p "$sentinel_port" -a "$SENTINEL_PASSWORD" sentinel masters 2>/dev/null || true)
            else
              temp_output=$(redis-cli -h "$sentinel_pod_fqdn" -p "$sentinel_port" sentinel masters 2>/dev/null || true)
            fi
            if [ -n "$temp_output" ]; then
              disconnected=false
              while read -r line; do
                  case "$line" in
                      flags)
                          read -r master_flags
                          if [[ "$master_flags" == *"disconnected"* ]]; then
                              disconnected=true
                          fi
                          ;;
                  esac
                  master_flags=""
              done <<< "$temp_output"
              if [ "$disconnected" = true ]; then
                  retry_count=$((retry_count + 1))
                  echo "one or more masters are disconnected. $retry_count/$max_retries failed. retrying..."
              else
                  echo "all masters are reachable."
                  success=true
                  output="$temp_output"
                  break
              fi
            else
              retry_count=$((retry_count + 1))
              echo "timeout waiting for $host to become available $retry_count/$max_retries failed. retrying..."
            fi
            sleep 1
          done
          if [ "$success" = true ]; then
            echo "connected to the sentinel successfully after $retry_count retries"
          else
            echo "sentinel is either starting up or encountering an issue."
          fi

          if [[ -n "$temp_output" ]]; then
            while read -r line; do
              case "$line" in
                name)
                  read -r pre_master_name
                  ;;
                ip)
                  read -r pre_master_ip
                  ;;
                port)
                  read -r pre_master_port
                  ;;
              esac
            done <<< "$temp_output"

            if [[ -z "$reference_master_name" && -z "$reference_master_ip" && -z "$reference_master_port" ]]; then
              reference_master_name="$master_name"
              reference_master_ip="$master_ip"
              reference_master_port="$master_port"
            else
              if [[ "$pre_master_name" != "$reference_master_name" || "$pre_master_ip" != "$reference_master_ip" || "$pre_master_port" != "$reference_master_port" ]]; then
                echo "the masters of the sentinels are different, configuration error."
                return 1
              fi
            fi
            output="$temp_output"
          fi
        done

        if [ -n "$output" ]; then
          echo "$output"
        else
          echo "sentinel is either initializing or has no monitored master nodes."
        fi
    else
        echo "SENTINEL_POD_FQDN_LIST environment variable is not set or empty."
        return 1
    fi

    if [[ -n "$output" ]]; then
        reset_redis_sentinel_monitor_conf
        local master_name master_ip master_port
        local master_down_after_milliseconds master_quorum master_failover_timeout master_parallel_syncs
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
                echo "REDIS_SENTINEL_PASSWORD environment variable is not set"
                return 1
            fi
            set -x
            sleep 30
            master_name="" master_ip="" master_port="" master_down_after_milliseconds=""
            master_quorum="" master_failover_timeout="" master_parallel_syncs=""
            fi
        done <<< "$output"
    else
        echo "initialization in progress, or unable to connect to redis sentinel, or no master nodes found."
    fi
}

start_redis_sentinel_server() {
  echo "Starting redis sentinel server..."
  exec redis-server /data/sentinel/redis-sentinel.conf --sentinel
  echo "Start redis sentinel server succeeded!"
}

check_redis_sentinel_member_leave_status
reset_redis_sentinel_conf
build_redis_sentinel_conf
recover_registered_redis_servers_if_needed
start_redis_sentinel_server