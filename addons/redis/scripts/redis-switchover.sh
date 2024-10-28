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

check_environment_exist(){
    if ! env_exist SENTINEL_POD_FQDN_LIST; then
        echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST: $SENTINEL_POD_FQDN_LIST is not set."
        exit 1
    fi

    if ! env_exist REDIS_COMPONENT_NAME; then
        echo "Error: Required environment variable REDIS_COMPONENT_NAME: $REDIS_COMPONENT_NAME is not set."
        exit 1
    fi
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

# Function to execute and log redis-cli command
execute_sub_command() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4

  local output
  local status

  # Check if password is provided, build the appropriate redis-cli command
  if ! is_empty "$password"; then
    output=$(redis-cli -h "$host" -p "$port" -a "$password" $command)
    status=$?
  else
    output=$(redis-cli -h "$host" -p "$port" $command)
    status=$?
  fi
  echo "$output"
  # Check if the command failed or the output is not "OK"
  if [ $status -ne 0 ] || ! equals "$output" "OK"; then
    echo "Command failed with status $status or output not OK."
    return 1
  else
    echo "Command executed successfully."
    return 0
  fi
}

redis_config_get(){
    local host=$1
    local port=$2
    local password=$3
    local command=$4

    local output
    local status

    # Check if password is provided, build the appropriate redis-cli command
    if ! is_empty "$password"; then
        output=$(redis-cli -h "$host" -p "$port" -a "$password" $command)
        status=$?
    else
        output=$(redis-cli -h "$host" -p "$port" $command)
        status=$?
    fi

    # Check if the command failed
    if [ $status -ne 0 ]; then
        echo "Command failed with status $status."
        return 1
    fi

    # Check if the output is empty
    if is_empty "$output"; then
        echo "Command returned no output."
        return 1
    fi

    echo "$output"
    return 0
}

switchoverWithCandidate() {
    redis_get_cmd="CONFIG GET replica-priority"
    redis_set_switchover_cmd="CONFIG SET replica-priority 1"
    unset_xtrace_when_ut_mode_false
    call_func_with_retry 3 5 check_connectivity "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" || exit 1
    current_replica_priority=$(redis_config_get "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" "$redis_get_cmd" | sed -n '2p')
    redis_set_recover_cmd="CONFIG SET replica-priority $current_replica_priority"
    call_func_with_retry 3 5 execute_sub_command "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" "$redis_set_switchover_cmd" || exit 1
    
    # TODO: check the role in kernel before switchover
    IFS=',' read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
    master_name="$REDIS_COMPONENT_NAME"
    local success=false

    for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
        if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "26379" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
            echo "Sentinel failover start with $sentinel_pod_fqdn, Switchover is processing"
            success=true
            break
        fi
    done

    if [ "$success" = false ]; then
        echo "All Sentinel failover attempts failed."
        exit 1
    fi
    # TODO: check switchover result
    call_func_with_retry 3 5 execute_sub_command "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" "$redis_set_recover_cmd" || exit 1
    set_xtrace_when_ut_mode_false
}

switchoverWithoutCandidate() {
    # TODO: check the role in kernel before switchover
    IFS=',' read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
    master_name="$REDIS_COMPONENT_NAME"
    local success=false
    unset_xtrace_when_ut_mode_false
    for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
        if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "26379" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
            echo "Sentinel failover start with $sentinel_pod_fqdn, Switchover is processing"
            success=true
            break
        fi
    done
    set_xtrace_when_ut_mode_false
    if [ "$success" = false ]; then
        echo "All Sentinel failover attempts failed."
        exit 1
    fi
    # TODO: check switchover result
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

#main
load_common_library
check_environment_exist
if ! env_exist KB_SWITCHOVER_CANDIDATE_FQDN; then
    switchoverWithoutCandidate
else
    switchoverWithCandidate
fi
