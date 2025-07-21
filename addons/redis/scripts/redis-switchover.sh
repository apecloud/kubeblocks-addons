#!/bin/bash

# shellcheck disable=SC2086
set -ex

call_func_with_retry() {
  local max_retries="$1"
  local retry_interval="$2"
  local function_name="$3"
  shift 3

  local retries=0
  while true; do
    if "$function_name" "$@"; then
      return 0
    else
      retries=$((retries + 1))
      if [[ $retries -eq $max_retries ]]; then
        echo "Function '$function_name' failed after $max_retries retries." >&2
        return 1
      fi
      echo "Function '$function_name' failed in $retries times. Retrying in $retry_interval seconds..." >&2
      sleep $retry_interval
    fi
  done
}

check_redis_role() {
  local host=$1
  local port=$2
  set +x
  local role_info
  if [[ -z "$REDIS_DEFAULT_PASSWORD" ]]; then
    role_info=$(redis-cli -h "$host" -p "$port" info replication)
  else
    role_info=$(redis-cli -h "$host" -p "$port" -a "$REDIS_DEFAULT_PASSWORD" info replication)
  fi
  set -x

  if [[ $? -ne 0 ]]; then
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

check_environment_exist() {
  local required_vars=(
    "SENTINEL_POD_NAME_LIST"
    "KB_POD_LIST"
    "SENTINEL_COMPONENT_NAME"
    "SERVICE_PORT"
    "SENTINEL_SERVICE_PORT"
    "KB_NAMESPACE"
    "KB_CLUSTER_COMP_NAME"
  )

  for var in "${required_vars[@]}"; do
    if [[ -z "${!var}" ]]; then
      echo "Error: Required environment variable $var is not set." >&2
      return 1
    fi
  done
}

check_connectivity() {
  local host=$1
  local port=$2
  local password=$3
  echo "Checking connectivity to $host on port $port using redis-cli..."
  local result
  if [[ -n "$password" ]]; then
    result=$(redis-cli -h "$host" -p "$port" -a "$password" PING)
  else
    result=$(redis-cli -h "$host" -p "$port" PING)
  fi

  if [[ "$result" == "PONG" ]]; then
    echo "$host is reachable on port $port."
    return 0
  else
    echo "$host is not reachable on port $port."
    return 1
  fi
}

execute_sub_command() {
  local host=$1
  local port=$2
  local password=$3
  local command=$4

  local output
  if [[ -n "$password" ]]; then
    output=$(redis-cli -h "$host" -p "$port" -a "$password" $command)
  else
    output=$(redis-cli -h "$host" -p "$port" $command)
  fi
  local status=$?

  echo "$output"
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
  if [[ -n "$password" ]]; then
    output=$(redis-cli -h "$host" -p "$port" -a "$password" $command)
  else
    output=$(redis-cli -h "$host" -p "$port" $command)
  fi
  local status=$?

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

check_redis_kernel_status() {
  local current_master=""
  local -a redis_pod_list
  IFS=',' read -ra redis_pod_list <<< "${KB_POD_LIST}"

  for redis_pod in "${redis_pod_list[@]}"; do
    local redis_pod_fqdn="$redis_pod.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    local role
    role=$(check_redis_role "$redis_pod_fqdn" "$SERVICE_PORT") || continue

    if [[ "$role" == "primary" ]]; then
      if [[ -n "$current_master" ]]; then
        echo "Error: Multiple masters detected" >&2
        return 1
      fi
      current_master="$redis_pod_fqdn"
    fi
  done

  if [[ -z "$current_master" ]]; then
    echo "Error: No master found" >&2
    return 1
  fi

  echo "$current_master"
  return 0
}

check_switchover_result() {
  local expected_master="$1"
  local max_wait=300
  local wait_interval=5
  local elapsed=0

  while [[ $elapsed -lt $max_wait ]]; do
    local current_master
    if current_master=$(check_redis_kernel_status); then
      if [[ "$current_master" = "$expected_master"* ]]; then
        echo "Switchover successful: $expected_master is now master"
        return 0
      fi
    fi
    sleep $wait_interval
    elapsed=$((elapsed + wait_interval))
  done

  echo "Switchover verification failed: expected master $expected_master not achieved" >&2
  return 1
}

execute_sentinel_failover() {
  local master_name=$1
  local success=false

  if [[ -z "$master_name" ]]; then
    # KB_CLUSTER_COMP_NAME is the redis component name
    master_name=$KB_CLUSTER_COMP_NAME
  fi

  local -a sentinel_pod_list
  IFS=',' read -ra sentinel_pod_list <<< "${SENTINEL_POD_NAME_LIST}"
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    local sentinel_pod_fqdn="$sentinel_pod.$SENTINEL_COMPONENT_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "$SENTINEL_SERVICE_PORT" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
      echo "Sentinel failover started with $sentinel_pod_fqdn"
      success=true
      break
    fi
  done

  if [[ "$success" == false ]]; then
    echo "All Sentinel failover attempts failed." >&2
    return 1
  fi
  return 0
}

switchover_with_candidate() {
  # check the role of candidate node before switchover
  local candidate_role
  candidate_role=$(check_redis_role "$KB_SWITCHOVER_CANDIDATE_FQDN" "$SERVICE_PORT")
  if [[ "$candidate_role" != "secondary" ]]; then
    echo "Error: Candidate node $KB_SWITCHOVER_CANDIDATE_FQDN is not in secondary role" >&2
    exit 1
  fi

  # check redis kernel role before switchover
  local initial_master
  initial_master=$(check_redis_kernel_status) || exit 1

  local redis_get_cmd="CONFIG GET replica-priority"
  local redis_set_switchover_cmd="CONFIG SET replica-priority 1"
  local redis_set_lowest_priority_cmd="CONFIG SET replica-priority 100"

  # set target candidate highest priority to make sure it will be promoted to master
  set +x
  declare -A original_priorities
  local -a redis_pod_list
  IFS=',' read -ra redis_pod_list <<< "${KB_POD_LIST}"
  for redis_pod in "${redis_pod_list[@]}"; do
    local redis_pod_fqdn="$redis_pod.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    call_func_with_retry 3 5 check_connectivity "$redis_pod_fqdn" "$SERVICE_PORT" "$REDIS_DEFAULT_PASSWORD" || exit 1
    local original_priority
    original_priority=$(redis_config_get "$redis_pod_fqdn" "$SERVICE_PORT" "$REDIS_DEFAULT_PASSWORD" "$redis_get_cmd" | sed -n '2p')
    original_priorities["$redis_pod_fqdn"]=$original_priority

    if [[ "$redis_pod_fqdn" = "$KB_SWITCHOVER_CANDIDATE_FQDN"* ]]; then
      call_func_with_retry 3 5 execute_sub_command "$redis_pod_fqdn" "$SERVICE_PORT" "$REDIS_DEFAULT_PASSWORD" "$redis_set_switchover_cmd" || exit 1
    else
      call_func_with_retry 3 5 execute_sub_command "$redis_pod_fqdn" "$SERVICE_PORT" "$REDIS_DEFAULT_PASSWORD" "$redis_set_lowest_priority_cmd" || exit 1
    fi
  done

  # do switchover
  execute_sentinel_failover "$CUSTOM_SENTINEL_MASTER_NAME" || exit 1

  # check switchover result
  check_switchover_result "$KB_SWITCHOVER_CANDIDATE_FQDN" || exit 1

  # recover all redis replica-priority
  echo "Recovering all Redis replica-priority..."
  for redis_pod in "${redis_pod_list[@]}"; do
    local redis_pod_fqdn="$redis_pod.$KB_CLUSTER_COMP_NAME-headless.$KB_NAMESPACE.svc.cluster.local"
    local redis_set_recover_cmd="CONFIG SET replica-priority ${original_priorities[$redis_pod_fqdn]}"
    call_func_with_retry 3 5 execute_sub_command "$redis_pod_fqdn" "$SERVICE_PORT" "$REDIS_DEFAULT_PASSWORD" "$redis_set_recover_cmd" || exit 1
  done
  set -x
  echo "All Redis config set replica-priority recovered."
}

switchover_without_candidate() {
  # check redis kernel role before switchover
  local initial_master
  initial_master=$(check_redis_kernel_status) || exit 1

  # do switchover
  set +x
  execute_sentinel_failover "$CUSTOM_SENTINEL_MASTER_NAME" || exit 1

  # check switchover result
  local max_wait=300
  local wait_interval=5
  local elapsed=0

  while [[ $elapsed -lt $max_wait ]]; do
    local current_master
    if current_master=$(check_redis_kernel_status); then
      if [[ "$current_master" != "$initial_master" ]]; then
        echo "Switchover successful: new master is $current_master"
        set -x
        return 0
      fi
    fi
    sleep $wait_interval
    elapsed=$((elapsed + wait_interval))
  done

  echo "Switchover verification failed: could not confirm new master" >&2
  set -x
  return 1
}

main() {
  if ! check_environment_exist; then
    exit 1
  fi

  if [[ -z "$KB_SWITCHOVER_CANDIDATE_FQDN" ]]; then
    switchover_without_candidate
  else
    switchover_with_candidate
  fi
}

# main
main "$@"