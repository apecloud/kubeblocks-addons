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

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
parse_redis_sentinel_announce_addr() {
  local pod_name="$1"

  if is_empty "${REDIS_SENTINEL_ADVERTISED_PORT}"; then
    echo "Environment variable REDIS_SENTINEL_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  # the value format of REDIS_SENTINEL_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  IFS=',' read -ra advertised_ports <<< "${REDIS_SENTINEL_ADVERTISED_PORT}"
  local found=false
  pod_name_ordinal=$(extract_obj_ordinal "$pod_name")
  for advertised_port in "${advertised_ports[@]}"; do
    # shellcheck disable=SC2207
    parts=($(split "$advertised_port" ":"))
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_obj_ordinal "$svc_name")
    if equals "$svc_name_ordinal" "$pod_name_ordinal"; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_SENTINEL_ADVERTISED_PORT: $REDIS_SENTINEL_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_sentinel_announce_port_value="$port"
      redis_sentinel_announce_host_value="$CURRENT_POD_HOST_IP"
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

  # hack for redis sentinel when nodeport is enabled, remove known-replica line which has the same nodeport port with master
  if [ -f $redis_sentinel_real_conf ] && ! is_empty "$REDIS_SENTINEL_ADVERTISED_PORT" && ! is_empty "$REDIS_SENTINEL_ADVERTISED_SVC_NAME"; then
    temp_file=$(mktemp)
    grep "^sentinel monitor" $redis_sentinel_real_conf > "$temp_file"
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
  if ! env_exist SENTINEL_POD_FQDN_LIST; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
    exit 1
  fi

  # build announce ip and port according to whether the announce addr is enabled
  if ! is_empty "$redis_sentinel_announce_host_value" && ! is_empty "$redis_sentinel_announce_port_value"; then
    echo "redis sentinel use nodeport $redis_sentinel_announce_host_value:$redis_sentinel_announce_port_value to announce"
    {
      echo "port $sentinel_port"
      echo "sentinel announce-ip $redis_sentinel_announce_host_value"
      echo "sentinel announce-port $redis_sentinel_announce_port_value"
    } >> $redis_sentinel_real_conf
  else
    # if the announce addr is not enabled, use the current pod fqdn to announce
    # shellcheck disable=SC2153
    current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$SENTINEL_POD_FQDN_LIST" "$CURRENT_POD_NAME")
    if is_empty "$current_pod_fqdn"; then
      echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from sentinel pod fqdn list: $SENTINEL_POD_FQDN_LIST. Exiting."
      exit 1
    fi
    echo "redis sentinel use current pod fqdn: $current_pod_fqdn to announce"
    {
      echo "port $sentinel_port"
      echo "sentinel announce-ip $current_pod_fqdn"
      echo "sentinel resolve-hostnames yes"
      echo "sentinel announce-hostnames yes"
    } >> $redis_sentinel_real_conf
  fi
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
parse_redis_sentinel_announce_addr "$CURRENT_POD_NAME"
reset_redis_sentinel_conf
build_redis_sentinel_conf
start_redis_sentinel_server