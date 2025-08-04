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

redis_announce_host_value=""
redis_announce_port_value=""
redis_default_service_port=6379
if [ -f /data/.fixed_pod_ip_enabled ]; then
  # if the file /data/.fixed_pod_ip_enabled exists, it means that the redis pod is running in fixed pod ip mode.
  FIXED_POD_IP_ENABLED=true
else
  FIXED_POD_IP_ENABLED=false
fi

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

extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$REDIS_ADVERTISED_LB_HOST" | tr ',' '\n' ); do
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

# TODO: if instanceTemplate is specified, the pod service could not be parsed from the pod ordinal.
parse_redis_primary_announce_addr() {
  if is_empty "$REDIS_ADVERTISED_PORT"; then
     REDIS_ADVERTISED_PORT="$REDIS_LB_ADVERTISED_PORT"
  fi
  if is_empty "$REDIS_ADVERTISED_PORT"; then
    echo "Environment variable REDIS_ADVERTISED_PORT not found. Ignoring."
    # if redis primary is in host network mode, use the host ip and port as the announce ip and port first
    if ! is_empty "${REDIS_HOST_NETWORK_PORT}"; then
      redis_announce_port_value="$REDIS_HOST_NETWORK_PORT"
      # the post provision action is executed in the primary pod, so we can get the host ip from the env defined in the action context.
      redis_announce_host_value="$CURRENT_POD_HOST_IP"
      echo "redis is in host network mode, use the host ip:$CURRENT_POD_HOST_IP and port:$REDIS_HOST_NETWORK_PORT as the announce ip and port."
    fi
    return 0
  fi

  local pod_name="$1"
  local found=false
  pod_name_ordinal=$(extract_obj_ordinal "$pod_name")
  # the value format of REDIS_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  # shellcheck disable=SC2207
  advertised_ports=($(split "$REDIS_ADVERTISED_PORT" ","))
  for advertised_port in "${advertised_ports[@]}"; do
    # shellcheck disable=SC2207
    parts=($(split "$advertised_port" ":"))
    local svc_name="${parts[0]}"
    local port="${parts[1]}"
    svc_name_ordinal=$(extract_obj_ordinal "$svc_name")
    if [[ "$svc_name_ordinal" == "$pod_name_ordinal" ]]; then
      echo "Found matching svcName and port for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. svcName: $svc_name, port: $port."
      redis_announce_port_value="$port"
      # TODO: get the host ip from env defined in the action context.
      lb_host=$(extract_lb_host_by_svc_name "$svc_name")
      if [ -n "$lb_host" ]; then
        echo "Found load balancer host for svcName '$svc_name', value is '$lb_host'."
        redis_announce_host_value="$lb_host"
        redis_announce_port_value="6379"
      else
        redis_announce_host_value="$CURRENT_POD_HOST_IP"
      fi
      found=true
      break
    fi
  done

  if equals "$found" false; then
    echo "Error: No matching svcName and port found for podName '$pod_name', REDIS_ADVERTISED_PORT: $REDIS_ADVERTISED_PORT. Exiting." >&2
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
      echo "Unknown command: $command" >&2
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
    echo "$host is not reachable on port $port." >&2
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
    echo "Command failed with status $status or output:$output not OK." >&2
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
    echo "Failed to get master address after maximum retries." >&2
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
  sentinel_configure_commands=("down-after-milliseconds" "failover-timeout" "parallel-syncs" "auth-pass")
  if [ "$IS_REDIS5" != "true" ]; then
    sentinel_configure_commands+=("auth-user")
  fi
  for cmd in "${sentinel_configure_commands[@]}"
  do
    sentinel_cli_cmd=$(construct_sentinel_sub_command "$cmd" "$master_name" "$redis_primary_host" "$redis_primary_port")
    call_func_with_retry 3 5 execute_sentinel_sub_command "$sentinel_host" "$sentinel_port" "$sentinel_cli_cmd" || exit 1
  done
  set_xtrace_when_ut_mode_false
  echo "redis sentinel register to $sentinel_host succeeded!"
}

function register_to_sentinel_for_redis5() {
  local sentinel_pod_fqdn=${1:? "Error: Required argument sentinel_pod_fqdn is not set."}
  sentinel_pod_ip=$(getent hosts "$sentinel_pod_fqdn" | awk '{ print $1 }')
  if [ -z "$sentinel_pod_ip" ]; then
    echo "Error: Failed to resolve pod ip for $sentinel_pod_fqdn."
    exit 1
  fi
  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value"; then
    echo "register to sentinel:$sentinel_pod_fqdn with announce addr: redis_announce_host_value=$redis_announce_host_value, redis_announce_port_value=$redis_announce_port_value"
    register_to_sentinel "$sentinel_pod_ip" "$master_name" "$redis_announce_host_value" "$redis_announce_port_value"
  elif [ "$FIXED_POD_IP_ENABLED" == "true" ]; then
    # the post provision action is executed in the primary pod, so we can get the primary pod ip from the env defined in the action context.
    echo "register to sentinel:$sentinel_pod_fqdn with fixed primary pod ip: fixed_pod_ip=$CURRENT_POD_IP, redis_default_service_port=$redis_default_service_port"
    register_to_sentinel "$sentinel_pod_ip" "$master_name" "$CURRENT_POD_IP" "$redis_default_service_port"
  else
    echo "register to sentinel:$sentinel_pod_fqdn with pod fqdn: redis_default_primary_pod_fqdn=$redis_default_primary_pod_fqdn, redis_default_service_port=$redis_default_service_port"
    register_to_sentinel "$sentinel_pod_ip" "$master_name" "$redis_default_primary_pod_fqdn" "$redis_default_service_port"
  fi
}

function register_to_sentinel_for_redis() {
  local sentinel_pod_fqdn=${1:? "Error: Required argument sentinel_pod_fqdn is not set."}
  if ! is_empty "$redis_announce_host_value" && ! is_empty "$redis_announce_port_value"; then
    echo "register to sentinel:$sentinel_pod_fqdn with announce addr: redis_announce_host_value=$redis_announce_host_value, redis_announce_port_value=$redis_announce_port_value"
    register_to_sentinel "$sentinel_pod_fqdn" "$master_name" "$redis_announce_host_value" "$redis_announce_port_value"
  elif [ "$FIXED_POD_IP_ENABLED" == "true" ]; then
    # the post provision action is executed in the primary pod, so we can get the primary pod ip from the env defined in the action context.
    echo "register to sentinel:$sentinel_pod_fqdn with fixed primary pod ip: fixed_pod_ip=$CURRENT_POD_IP, redis_default_service_port=$redis_default_service_port"
    register_to_sentinel "$sentinel_pod_fqdn" "$master_name" "$CURRENT_POD_IP" "$redis_default_service_port"
  else
    echo "register to sentinel:$sentinel_pod_fqdn with pod fqdn: redis_default_primary_pod_fqdn=$redis_default_primary_pod_fqdn, redis_default_service_port=$redis_default_service_port"
    register_to_sentinel "$sentinel_pod_fqdn" "$master_name" "$redis_default_primary_pod_fqdn" "$redis_default_service_port"
  fi
}

register_to_sentinel_wrapper() {
  # check required environment variables, we use REDIS_COMPONENT_NAME as the master_name registered to sentinel
  if is_empty "$REDIS_COMPONENT_NAME" || is_empty "$REDIS_POD_NAME_LIST"; then
    echo "Error: Required environment variable REDIS_COMPONENT_NAME and REDIS_POD_NAME_LIST is not set." >&2
    return 1
  fi

  # parse redis sentinel pod fqdn list from $SENTINEL_POD_FQDN_LIST env
  # shellcheck disable=SC2153
  if is_empty "$SENTINEL_POD_FQDN_LIST"; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST is not set." >&2
    return 1
  fi

  # get minimum lexicographical order pod name as default primary node (the same logic as redis initialize primary node selection)
  redis_default_primary_pod_name=$(min_lexicographical_order_pod "$REDIS_POD_NAME_LIST")
  redis_default_primary_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$REDIS_POD_FQDN_LIST" "$redis_default_primary_pod_name")
  init_redis_service_port
  parse_redis_primary_announce_addr "$redis_default_primary_pod_name"
  if is_empty "$CUSTOM_SENTINEL_MASTER_NAME"; then
    master_name=$REDIS_COMPONENT_NAME
  else
    master_name="$CUSTOM_SENTINEL_MASTER_NAME"
  fi
  sentinel_pod_fqdn_list=($(split "$SENTINEL_POD_FQDN_LIST" ","))
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    if [ "$IS_REDIS5" == "true" ]; then
       register_to_sentinel_for_redis5 "${sentinel_pod}"
    else
       register_to_sentinel_for_redis "${sentinel_pod}"
    fi
  done
}

# Notice: make sure post provision action execute in redis primary pod by kbagent
register_to_sentinel_if_needed() {
  if ! is_empty "$SENTINEL_COMPONENT_NAME"; then
    echo "redis sentinel component found, register to redis sentinel."
    if ! register_to_sentinel_wrapper; then
      echo "Failed to register to sentinel." >&2
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

