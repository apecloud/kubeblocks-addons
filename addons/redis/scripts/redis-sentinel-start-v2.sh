#!/bin/bash

# Based on the Component Definition API, Redis Sentinel deployed independently

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
#
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

set_xtrace() {
  if [ "false" == "$ut_mode" ]; then
    set -x
  fi
}

unset_xtrace() {
  if [ "false" == "$ut_mode" ]; then
    set +x
  fi
}

redis_sentinel_sleep(){
  time="$1"
  if [ "false" == "$ut_mode" ]; then
    sleep "$time"
  fi
}

redis_sentinel_real_conf="/data/sentinel/redis-sentinel.conf"
redis_sentinel_init_conf="/data/sentinel/init_done.conf"

reset_redis_sentinel_conf() {
  echo "reset redis sentinel conf"
  sentinel_port=26379
  if env_exist SENTINEL_SERVICE_PORT; then
    sentinel_port=$SENTINEL_SERVICE_PORT
  fi
  mkdir -p /data/sentinel
  if [ -f $redis_sentinel_real_conf ]; then
    sed -i "" "/sentinel announce-ip/d"
    sed -i "" "/sentinel resolve-hostnames/d" $redis_sentinel_real_conf
    sed -i "" "/sentinel announce-hostnames/d" $redis_sentinel_real_conf
    unset_xtrace
    if [ -n "$SENTINEL_PASSWORD" ]; then
      sed -i "" "/sentinel sentinel-user/d" $redis_sentinel_real_conf
      sed -i "" "/sentinel sentinel-pass/d" $redis_sentinel_real_conf
    fi
    set_xtrace
    sed -i "" "/port $sentinel_port/d" $redis_sentinel_real_conf
  fi
}

build_redis_sentinel_conf() {
  echo "build redis sentinel conf"
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$SENTINEL_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_empty "$current_pod_fqdn"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from sentinel pod fqdn list: $SENTINEL_POD_FQDN_LIST. Exiting."
    exit 1
  fi
  {
    echo "port $sentinel_port"
    echo "sentinel announce-ip $current_pod_fqdn"
    echo "sentinel resolve-hostnames yes"
    echo "sentinel announce-hostnames yes"
  } >> $redis_sentinel_real_conf
  unset_xtrace
  if [ -n "$SENTINEL_PASSWORD" ]; then
    echo "sentinel sentinel-user $SENTINEL_USER" >> $redis_sentinel_real_conf
    echo "sentinel sentinel-pass $SENTINEL_PASSWORD" >> $redis_sentinel_real_conf
  fi
  set_xtrace
  echo "build redis sentinel conf succeeded!"
}

recover_registered_redis_servers_if_needed() {
  if [ -f $redis_sentinel_init_conf ]; then
    echo "normal start"
  else
    echo "horizontal scaling"
    if recover_registered_redis_servers; then
      touch "$redis_sentinel_init_conf"
    else
      echo "recover_registered_redis_servers failed"
      exit 1
    fi
  fi
}

reset_redis_sentinel_monitor_conf() {
    echo "reset sentinel monitor configuration file if there are any residual configurations "
    if [ -f $redis_sentinel_real_conf ]; then
      sed -i "" "/sentinel monitor/d" $redis_sentinel_real_conf
      sed -i "" "/sentinel down-after-milliseconds/d" $redis_sentinel_real_conf
      sed -i "" "/sentinel failover-timeout/d" $redis_sentinel_real_conf
      sed -i "" "/sentinel parallel-syncs/d" $redis_sentinel_real_conf
      unset_xtrace
      if [[ -v REDIS_SENTINEL_PASSWORD ]]; then
        sed -i "" "/sentinel auth-user/d" $redis_sentinel_real_conf
        sed -i "" "/sentinel auth-pass/d" $redis_sentinel_real_conf
      fi
      set_xtrace
    fi
}

temp_output=""
redis_sentinel_get_masters() {
  local host=$1
  local port=$2
  if [ -n "$SENTINEL_PASSWORD" ]; then
    temp_output=$(redis-cli -h "$host" -p "$port" -a "$SENTINEL_PASSWORD" sentinel masters 2>/dev/null || true)
  else
    temp_output=$(redis-cli -h "$host" -p "$port" sentinel masters 2>/dev/null || true)
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
            redis_sentinel_get_masters $sentinel_pod_fqdn $sentinel_port
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
                  break
              fi
            else
              retry_count=$((retry_count + 1))
              echo "timeout waiting for $host to become available $retry_count/$max_retries failed. retrying..."
            fi
            redis_sentinel_sleep 1
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
            echo "sentinel monitor $master_name $master_ip $master_port $master_quorum" >> $redis_sentinel_real_conf
            echo "sentinel down-after-milliseconds $master_name $master_down_after_milliseconds" >> $redis_sentinel_real_conf
            echo "sentinel failover-timeout $master_name $master_failover_timeout" >> $redis_sentinel_real_conf
            echo "sentinel parallel-syncs $master_name $master_parallel_syncs" >> $redis_sentinel_real_conf
            echo "sentinel auth-user $master_name $REDIS_SENTINEL_USER" >> $redis_sentinel_real_conf
            cluster_name="$KB_CLUSTER_NAME"
            comp_name="${master_name#"$cluster_name"-}"
            comp_name_upper=$(echo "$comp_name" | tr '[:lower:]' '[:upper:]')
            unset_xtrace
            if [[ -v REDIS_SENTINEL_PASSWORD ]]; then
                var_name="REDIS_SENTINEL_PASSWORD_${comp_name_upper}"
                if [[ -n "${!var_name}" ]]; then
                  auth_pass="${!var_name}"
                else
                  auth_pass="$REDIS_SENTINEL_PASSWORD"
                fi
                echo "sentinel auth-pass $master_name $auth_pass" >> $redis_sentinel_real_conf
            else
                echo "REDIS_SENTINEL_PASSWORD environment variable is not set"
                return 1
            fi
            set_xtrace
            redis_sentinel_sleep 30
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
  exec redis-server $redis_sentinel_real_conf --sentinel
  echo "Start redis sentinel server succeeded!"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
reset_redis_sentinel_conf
build_redis_sentinel_conf
recover_registered_redis_servers_if_needed
start_redis_sentinel_server