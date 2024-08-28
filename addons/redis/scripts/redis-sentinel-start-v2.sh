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
start_redis_sentinel_server