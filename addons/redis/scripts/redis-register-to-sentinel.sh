#!/bin/bash

# Based on the Component Definition API, Redis deployed independently, this script is used to register Redis to Sentinel.
# And the script will only be executed once during the initialization of the Redis cluster.

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
# shellcheck disable=SC2128
# shellcheck disable=SC2207
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

redis_advertised_svc_host_value=""
redis_advertised_svc_port_value=""
redis_default_service_port=6379

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

init_redis_service_port() {
  if env_exist SERVICE_PORT; then
    redis_default_service_port=$SERVICE_PORT
  fi
}

# TODO: it will be removed in the future
extract_ordinal_from_object_name() {
  local object_name="$1"
  local ordinal="${object_name##*-}"
  echo "$ordinal"
}

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
parse_redis_advertised_svc_if_exist() {
  local pod_name="$1"

  if ! env_exist REDIS_ADVERTISED_PORT; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  local found=false
  pod_name_ordinal=$(extract_ordinal_from_object_name "$pod_name")
  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  # shellcheck disable=SC2207
  advertised_ports=($(split "$REDIS_ADVERTISED_PORT" ","))
  for advertised_port in "${advertised_ports[@]}"; do
    # shellcheck disable=SC2207
    parts=($(split "$advertised_port" ":"))
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_ordinal_from_object_name "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_advertised_svc_port_value="$port"
      # TODO: get the host ip from env defined in the action context.
      redis_advertised_svc_host_value="$CURRENT_POD_HOST_IP"
      found=true
      break
    fi
  done

  if equals "$found" false; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting."
    exit 1
  fi
}

construct_sentinel_sub_command() {
  local command=$1
  local master_name=$2
  local redis_primary_host=$3
  local redis_primary_port=$4

  case $command in
    "monitor")
      echo "SENTINEL monitor $master_name $redis_primary_host $redis_primary_port 2"
      ;;
    "down-after-milliseconds")
      echo "SENTINEL set $master_name down-after-milliseconds 5000"
      ;;
    "failover-timeout")
      echo "SENTINEL set $master_name failover-timeout 60000"
      ;;
    "parallel-syncs")
      echo "SENTINEL set $master_name parallel-syncs 1"
      ;;
    "auth-user")
      echo "SENTINEL set $master_name auth-user $REDIS_SENTINEL_USER"
      ;;
    "auth-pass")
      echo "SENTINEL set $master_name auth-pass $REDIS_SENTINEL_PASSWORD"
      ;;
    *)
      echo "Unknown command: $command"
      return 1
      ;;
  esac
}

check_connectivity() {
  local host=$1
  local port=$2
  local password=$3
  echo "Checking connectivity to $host on port $port using redis-cli..."
  if redis-cli -h "$host" -p "$port" -a "$password" PING | grep -q "PONG"; then
    echo "$host is reachable on port $port."
    return 0
  else
    echo "$host is not reachable on port $port."
    return 1
  fi
}

# function to execute and log redis-cli command
execute_sentinel_sub_command() {
  local sentinel_host=$1
  local sentinel_port=$2
  local command=$3

  local output
  output=$(redis-cli -h "$sentinel_host" -p "$sentinel_port" -a "$SENTINEL_PASSWORD" $command)
  local status=$?
  echo "$output"

  if [ $status -ne 0 ] || ! equals "$output" "OK"; then
    echo "Command failed with status $status or output not OK."
    return 1
  else
    echo "Command executed successfully."
    return 0
  fi
}

get_master_addr_by_name(){
  local sentinel_host=$1
  local sentinel_port=$2
  local command=$3
  local output
  output=$(redis-cli -h "$sentinel_host" -p "$sentinel_port" -a "$SENTINEL_PASSWORD" $command)
  local status=$?
  if [ $status -ne 0 ]; then
    echo "Command failed with status $status." >&2
    return 1
  fi
  local ip_addr=$(echo "$output" | head -n1)
  if is_empty "$ip_addr" || echo "$ip_addr" | grep -E '^([a-zA-Z0-9-]+\.[a-zA-Z0-9-]+\.default\.svc|([0-9]{1,3}\.){3}[0-9]{1,3})$' > /dev/null; then
    echo "$output" 
    return 0
  else
    echo "Command failed with $output" >&2
    return 1
  fi
}

# usage: register_to_sentinel <sentinel_host> <master_name> <redis_primary_host> <redis_primary_port>
# redis sentinel configuration refer: https://redis.io/docs/management/sentinel/#configuring-sentinel
register_to_sentinel() {
  local sentinel_host=$1
  local master_name=$2
  local sentinel_port=${SENTINEL_SERVICE_PORT:-26379}
  local redis_primary_host=$3
  local redis_primary_port=$4

  unset_xtrace_when_ut_mode_false
  # Check connectivity to sentinel host and redis primary host
  call_func_with_retry 3 5 check_connectivity "$sentinel_host" "$sentinel_port" "$SENTINEL_PASSWORD" || exit 1
  call_func_with_retry 3 5 check_connectivity "$redis_primary_host" "$redis_primary_port" "$REDIS_DEFAULT_PASSWORD" || exit 1

  # Check if Sentinel is already monitoring the Redis primary
  if ! master_addr=$(call_func_with_retry 3 5 get_master_addr_by_name "$sentinel_host" "$sentinel_port" "SENTINEL get-master-addr-by-name $master_name"); then
    echo "Failed to get master address after maximum retries."
    exit 1
  fi
  if is_empty "$master_addr"; then
    echo "Sentinel is not monitoring $master_name. Registering it..."
    # Register the Redis primary with Sentinel
    sentinel_monitor_cmd="SENTINEL monitor $master_name $redis_primary_host $redis_primary_port 2"
    call_func_with_retry 3 5 execute_sentinel_sub_command "$sentinel_host" "$sentinel_port" "$sentinel_monitor_cmd" || exit 1
  else
    echo "Sentinel is already monitoring $master_name at $master_addr. Skipping monitor registration."
  fi
  #configure the Redis primary with Sentinel
  sentinel_configure_commands=("down-after-milliseconds" "failover-timeout" "parallel-syncs" "auth-user" "auth-pass")
  for cmd in "${sentinel_configure_commands[@]}"
  do
    sentinel_cli_cmd=$(construct_sentinel_sub_command "$cmd" "$master_name" "$redis_primary_host" "$redis_primary_port")
    call_func_with_retry 3 5 execute_sentinel_sub_command "$sentinel_host" "$sentinel_port" "$sentinel_cli_cmd" || exit 1
  done
  set_xtrace_when_ut_mode_false
  echo "redis sentinel register to $sentinel_host succeeded!"
}

register_to_sentinel_wrapper() {
  # check required environment variables, we use REDIS_COMPONENT_NAME as the master_name registered to sentinel
  if  ! env_exists REDIS_COMPONENT_NAME REDIS_POD_NAME_LIST; then
    echo "Error: Required environment variable REDIS_COMPONENT_NAME and REDIS_POD_NAME_LIST is not set."
    return 1
  fi

  # parse redis sentinel pod fqdn list from $SENTINEL_POD_FQDN_LIST env
  if ! env_exist SENTINEL_POD_FQDN_LIST; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set."
    return 1
  fi

  # get minimum lexicographical order pod name as default primary node (the same logic as redis initialize primary node selection)
  redis_default_primary_pod_name=$(min_lexicographical_order_pod "$REDIS_POD_NAME_LIST")
  redis_default_primary_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$REDIS_POD_FQDN_LIST" "$redis_default_primary_pod_name")
  init_redis_service_port
  parse_redis_advertised_svc_if_exist "$redis_default_primary_pod_name"

  sentinel_pod_fqdn_list=($(split "$SENTINEL_POD_FQDN_LIST" ","))
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    if ! is_empty "$redis_advertised_svc_host_value" && ! is_empty "$redis_advertised_svc_port_value"; then
      echo "register to sentinel:$sentinel_pod_fqdn with advertised service: redis_advertised_svc_host_value=$redis_advertised_svc_host_value, redis_advertised_svc_port_value=$redis_advertised_svc_port_value"
      register_to_sentinel "$sentinel_pod_fqdn" "$REDIS_COMPONENT_NAME" "$redis_advertised_svc_host_value" "$redis_advertised_svc_port_value"
    else
      echo "register to sentinel:$sentinel_pod_fqdn with pod fqdn: redis_default_primary_pod_fqdn=$redis_default_primary_pod_fqdn, redis_default_service_port=$redis_default_service_port"
      register_to_sentinel "$sentinel_pod_fqdn" "$REDIS_COMPONENT_NAME" "$redis_default_primary_pod_fqdn" "$redis_default_service_port"
    fi
  done
}

register_to_sentinel_if_needed() {
  if env_exist SENTINEL_COMPONENT_NAME; then
    echo "redis sentinel component found, register to redis sentinel."
    if ! register_to_sentinel_wrapper; then
      echo "Failed to register to sentinel."
      exit 1
    fi
  else
    echo "redis sentinel component not found, skip register to sentinel."
    return 0
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
register_to_sentinel_if_needed

