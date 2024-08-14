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

redis_sentinel_conf_dir="/data/sentinel"
redis_sentinel_real_conf="/data/sentinel/redis-sentinel.conf"
redis_sentinel_real_conf_bak="/data/sentinel/redis-sentinel.conf.bak"
redis_sentinel_init_conf="/data/sentinel/init_done.conf"

reset_redis_sentinel_conf() {
  echo "reset redis sentinel conf"
  sentinel_port=26379
  if env_exist SENTINEL_SERVICE_PORT; then
    sentinel_port=$SENTINEL_SERVICE_PORT
  fi
  mkdir -p $redis_sentinel_conf_dir
  if [ -f $redis_sentinel_real_conf ]; then
    sed "/sentinel announce-ip/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
    sed "/sentinel resolve-hostnames/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
    sed "/sentinel announce-hostnames/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
    unset_xtrace_when_ut_mode_false
    if [ -n "$SENTINEL_PASSWORD" ]; then
      sed "/sentinel sentinel-user/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
      sed "/sentinel sentinel-pass/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
    fi
    set_xtrace_when_ut_mode_false
    sed "/port $sentinel_port/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
  fi
}

build_redis_sentinel_conf() {
  echo "build redis sentinel conf"
  if ! env_exist SENTINEL_POD_FQDN_LIST; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
    exit 1
  fi
  # shellcheck disable=SC2153
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
  unset_xtrace_when_ut_mode_false
  if [ -n "$SENTINEL_PASSWORD" ]; then
    {
      echo "sentinel sentinel-user $SENTINEL_USER"
      echo "sentinel sentinel-pass $SENTINEL_PASSWORD"
    } >> $redis_sentinel_real_conf
  fi
  set_xtrace_when_ut_mode_false
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
      sed "/sentinel monitor/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
      sed "/sentinel down-after-milliseconds/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
      sed "/sentinel failover-timeout/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
      sed "/sentinel parallel-syncs/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
      unset_xtrace_when_ut_mode_false
      if [[ -v REDIS_SENTINEL_PASSWORD ]]; then
        sed "/sentinel auth-user/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
        sed "/sentinel auth-pass/d" $redis_sentinel_real_conf > $redis_sentinel_real_conf_bak && mv $redis_sentinel_real_conf_bak $redis_sentinel_real_conf
      fi
      set_xtrace_when_ut_mode_false
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
  if ! env_exist SENTINEL_POD_FQDN_LIST; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
    return 1
  fi

  output=""
  local max_retries=5
  local retry_count=0
  local success=false
  # shellcheck disable=SC2207
  sentinel_pod_fqdn_list=($(split "$SENTINEL_POD_FQDN_LIST" ","))
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    while [ $retry_count -lt $max_retries ]; do
      redis_sentinel_get_masters "$sentinel_pod_fqdn" "$sentinel_port"
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
      sleep_when_ut_mode_false 1
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

  if is_empty "$output"; then
    echo "initialization in progress, or unable to connect to redis sentinel, or no master nodes found."
    return 0
  fi

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
      echo "master-name: $master_name, master-ip: $master_ip, master-port: $master_port, \
      down-after-milliseconds: $master_down_after_milliseconds, \
      failover-timeout: $master_failover_timeout, \
      parallel-syncs: $master_parallel_syncs, quorum: $master_quorum"
      cluster_name="$KB_CLUSTER_NAME"
      comp_name="${master_name#"$cluster_name"-}"
      comp_name_upper=$(echo "$comp_name" | tr '[:lower:]' '[:upper:]')
      unset_xtrace_when_ut_mode_false
      if ! env_exist REDIS_SENTINEL_PASSWORD; then
        echo "REDIS_SENTINEL_PASSWORD environment variable is not set"
        return 1
      fi
      var_name="REDIS_SENTINEL_PASSWORD_${comp_name_upper}"
      if [[ -n "${!var_name}" ]]; then
        auth_pass="${!var_name}"
      else
        auth_pass="$REDIS_SENTINEL_PASSWORD"
      fi
      {
        echo "sentinel monitor $master_name $master_ip $master_port $master_quorum"
        echo "sentinel down-after-milliseconds $master_name $master_down_after_milliseconds"
        echo "sentinel failover-timeout $master_name $master_failover_timeout"
        echo "sentinel parallel-syncs $master_name $master_parallel_syncs"
        echo "sentinel auth-user $master_name $REDIS_SENTINEL_USER"
        echo "sentinel auth-pass $master_name $auth_pass"
      } >> $redis_sentinel_real_conf
      set_xtrace_when_ut_mode_false
      sleep_when_ut_mode_false 30
      master_name="" master_ip="" master_port="" master_down_after_milliseconds=""
      master_quorum="" master_failover_timeout="" master_parallel_syncs=""
    fi
  done <<< "$output"
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