#!/bin/bash

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
# shellcheck disable=SC2153
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

declare -A ORIGINAL_PRIORITIES
redis_service_port=$SERVICE_PORT
if [ "$TLS_ENABLED" == "true" ]; then
  redis_service_port=$NON_TLS_SERVICE_PORT
fi

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

check_environment_exist() {
  local required_vars=(
    "SENTINEL_POD_FQDN_LIST"
    "REDIS_POD_FQDN_LIST"
    "REDIS_COMPONENT_NAME"
  )

  if [[ ${COMPONENT_REPLICAS} -lt 2 ]]; then
    exit 0
  fi

  for var in "${required_vars[@]}"; do
    if is_empty "${!var}"; then
      echo "Error: Required environment variable $var is not set." >&2
      return 1
    fi
  done

  if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
    echo "switchover not triggered for primary, nothing to do, exit 0."
    exit 0
  fi
}

check_redis_role() {
  local host=$1
  local port=$2
  unset_xtrace_when_ut_mode_false
  local role_info
  if [[ -z "$REDIS_DEFAULT_PASSWORD" ]]; then
    role_info=$(redis-cli -h "$host" -p "$port" info replication)
  else
    role_info=$(redis-cli -h "$host" -p "$port" -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  status=$?
  set_xtrace_when_ut_mode_false

  if [[ $status -ne 0 ]]; then
    echo "Failed to get role info from $host" >&2
    return 1
  fi

  if echo "$role_info" | grep -q "^role:master"; then
    echo "primary"
  elif echo "$role_info" | grep -q "^role:slave"; then
    echo "secondary"
  else
    echo "unknown"
    return 1
  fi
}

check_redis_kernel_status() {
  local role
  local current_master=""
  local -a redis_pod_fqdn_list
  IFS=',' read -ra redis_pod_fqdn_list <<< "${REDIS_POD_FQDN_LIST}"
  for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
    role=$(check_redis_role "$redis_pod_fqdn" "$redis_service_port") || continue
    if [[ "$role" == "primary" ]]; then
      if [[ -n "$current_master" ]]; then
        echo "Error: Multiple primaries detected" >&2
        return 1
      fi
      current_master="$redis_pod_fqdn"
    fi
  done

  if [[ -z "$current_master" ]]; then
    echo "Error: No primary found" >&2
    return 1
  fi

  echo "$current_master"
  return 0
}

check_switchover_result() {
  local expected_master="$1"
  local initial_master="$2"
  local max_wait=300
  local wait_interval=5
  local elapsed=0

  while [[ $elapsed -lt $max_wait ]]; do
    local current_master
    if current_master=$(check_redis_kernel_status); then
      # if expected_master is specified, check if it is achieved
      if ! is_empty "$expected_master"; then
        if [[ "$current_master" = "$expected_master"* ]]; then
          echo "Switchover successful: $expected_master is now master"
          return 0
        fi
      # if initial_master is specified, check if it is switched to a different node
      elif ! is_empty "$initial_master"; then
        if [[ "$current_master" != "$initial_master" ]]; then
          echo "Switchover successful: new master is $current_master"
          return 0
        fi
      else
        echo "Error: Neither expected_master nor initial_master specified" >&2
        return 1
      fi
    fi
    sleep_when_ut_mode_false $wait_interval
    elapsed=$((elapsed + wait_interval))
  done

  if ! is_empty "$expected_master"; then
    echo "Switchover verification failed: expected master $expected_master not achieved" >&2
  else
    echo "Switchover verification failed: could not confirm new master" >&2
  fi
  return 1
}

check_connectivity() {
  local host=$1
  local port=$2
  local password=$3
  echo "Checking connectivity to $host on port $port using redis-cli..."
  local result
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    result=$(redis-cli -h "$host" -p "$port" -a "$password" PING)
  else
    result=$(redis-cli -h "$host" -p "$port" PING)
  fi
  set_xtrace_when_ut_mode_false
  if [[ "$result" == "PONG" ]]; then
    echo "$host is reachable on port $port."
    return 0
  else
    echo "$host is not reachable on port $port." >&2
    return 1
  fi
}

execute_sub_command() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4

  local output
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    output=$(redis-cli -h "$host" -p "$port" -a "$password" $command)
  else
    output=$(redis-cli -h "$host" -p "$port" $command)
  fi
  local status=$?
  set_xtrace_when_ut_mode_false

  echo "execute_sub_command output: $output"
  if [[ $status -ne 0 ]] || [[ "$output" != "OK" ]]; then
    echo "Command failed with status $status or output not OK." >&2
    return 1
  fi
  echo "Command executed successfully."
  return 0
}

redis_config_get() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4

  local output
  unset_xtrace_when_ut_mode_false
  if ! is_empty "$password"; then
    output=$(redis-cli -h "$host" -p "$port" -a "$password" $command)
  else
    output=$(redis-cli -h "$host" -p "$port" $command)
  fi
  local status=$?
  set_xtrace_when_ut_mode_false

  if [[ $status -ne 0 ]]; then
    echo "Command failed with status $status." >&2
    return 1
  fi

  if [[ -z "$output" ]]; then
    echo "Command returned no output." >&2
    return 1
  fi

  echo "$output"
  return 0
}

execute_sentinel_failover() {
  local master_name=$1
  local success=false

  if [[ -z "$master_name" ]]; then
    master_name=$REDIS_COMPONENT_NAME
  fi

  local -a sentinel_pod_fqdn_list
  IFS=',' read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
  unset_xtrace_when_ut_mode_false
  for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
    if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "$SENTINEL_SERVICE_PORT" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
      echo "Sentinel failover started with $sentinel_pod_fqdn"
      success=true
      break
    fi
  done
  set_xtrace_when_ut_mode_false

  if [[ "$success" == false ]]; then
    echo "All Sentinel failover attempts failed." >&2
    return 1
  fi
  return 0
}

# set target candidate highest priority to make sure it will be promoted to master
set_redis_priorities() {
  local candidate_fqdn="$1"

  local -a redis_pod_fqdn_list
  IFS=',' read -ra redis_pod_fqdn_list <<< "${REDIS_POD_FQDN_LIST}"
  for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
    call_func_with_retry 3 5 check_connectivity "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" || return 1

    # Get original priority
    local redis_get_cmd="CONFIG GET replica-priority"
    local original_priority
    original_priority=$(redis_config_get "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" "$redis_get_cmd" | sed -n '2p')
    status=$?
    if [ $status -ne 0 ]; then
      echo "Error: Failed to get replica-priority for $redis_pod_fqdn" >&2
      return 1
    fi

    # Save original priority to global variable
    ORIGINAL_PRIORITIES[$redis_pod_fqdn]=$original_priority

    local redis_set_cmd
    if [[ "$redis_pod_fqdn" = "$candidate_fqdn"* ]]; then
      redis_set_cmd="CONFIG SET replica-priority 1"
    else
      redis_set_cmd="CONFIG SET replica-priority 100"
    fi

    call_func_with_retry 3 5 execute_sub_command "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" "$redis_set_cmd" || return 1
  done
  return 0
}

# recover all redis replica-priority
recover_redis_priorities() {
  local -a redis_pod_fqdn_list
  IFS=',' read -ra redis_pod_fqdn_list <<< "${REDIS_POD_FQDN_LIST}"

  echo "Recovering all Redis replica-priority..."
  for redis_pod_fqdn in "${redis_pod_fqdn_list[@]}"; do
    local redis_set_recover_cmd="CONFIG SET replica-priority ${ORIGINAL_PRIORITIES[$redis_pod_fqdn]}"
    call_func_with_retry 3 5 execute_sub_command "$redis_pod_fqdn" "$redis_service_port" "$REDIS_DEFAULT_PASSWORD" "$redis_set_recover_cmd" || return 1
  done
  echo "All Redis config set replica-priority recovered."
  return 0
}

switchover_with_candidate() {
  # check the role of candidate before switchover
  local candidate_role
  candidate_role=$(check_redis_role "$KB_SWITCHOVER_CANDIDATE_FQDN" "$redis_service_port")
  if [[ "$candidate_role" != "secondary" ]]; then
    echo "Error: Candidate node $KB_SWITCHOVER_CANDIDATE_FQDN is not in secondary role" >&2
    return 1
  fi

  # check redis kernel role before switchover
  local initial_master
  initial_master=$(check_redis_kernel_status) || return 1

  local redis_get_cmd="CONFIG GET replica-priority"
  local redis_set_switchover_cmd="CONFIG SET replica-priority 1"
  local redis_set_lowest_priority_cmd="CONFIG SET replica-priority 100"

  # set target candidate highest priority to make sure it will be promoted to master
  unset_xtrace_when_ut_mode_false
  set_redis_priorities "$KB_SWITCHOVER_CANDIDATE_FQDN" || return 1

  # do switchover
  execute_sentinel_failover "$CUSTOM_SENTINEL_MASTER_NAME" || return 1

  # check switchover result
  check_switchover_result "$KB_SWITCHOVER_CANDIDATE_FQDN" "" || return 1

  # recover all redis replica-priority
  echo "Recovering all Redis replica-priority..."
  recover_redis_priorities || return 1

  set_xtrace_when_ut_mode_false
  echo "All Redis config set replica-priority recovered."
}

switchover_without_candidate() {
  # check redis kernel role before switchover
  local initial_master
  initial_master=$(check_redis_kernel_status) || return 1

  # do switchover
  execute_sentinel_failover "$CUSTOM_SENTINEL_MASTER_NAME" || return 1

  # check switchover result using initial_master
  # if no candidate specified, skip check
  # check_switchover_result "" "$initial_master" || return 1
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
check_environment_exist || exit 1
if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
  switchover_without_candidate || exit 1
else
  switchover_with_candidate || exit 1
fi
