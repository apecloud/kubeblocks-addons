#!/bin/bash
set -ex

if ! env_exists "$SENTINEL_POD_FQDN_LIST"; then
    echo "Error: Required environment variable SENTINEL_POD_FQDN_LIST: $SENTINEL_POD_FQDN_LIST is not set."
    exit 1
fi

if ! env_exists "$REDIS_COMPONENT_NAME"; then
    echo "Error: Required environment variable REDIS_COMPONENT_NAME: $REDIS_COMPONENT_NAME is not set."
    exit 1
fi

old_ifs="$IFS"
IFS=','
set -f
read -ra sentinel_pod_fqdn_list <<< "${SENTINEL_POD_FQDN_LIST}"
set +f
IFS="$old_ifs"

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
    if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
        echo "Error: Required environment variable KB_SWITCHOVER_CANDIDATE_FQDN: $KB_SWITCHOVER_CANDIDATE_FQDN is not set."
        exit 1
    fi

    redis_get_cmd="CONFIG GET replica-priority"
    redis_set_switchover_cmd="CONFIG SET replica-priority 1"

    if is_empty "$REDIS_DEFAULT_PASSWORD"; then
        call_func_with_retry 3 5 check_connectivity "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" || exit 1
    else
        call_func_with_retry 3 5 check_connectivity "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" || exit 1
    fi

    if is_empty "$REDIS_DEFAULT_PASSWORD"; then
        current_replica_priority=$(redis_config_get "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" "$redis_get_cmd" | sed -n '2p')
    else 
        current_replica_priority=$(redis_config_get "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$redis_get_cmd" | sed -n '2p')
    fi

    redis_set_recover_cmd="CONFIG SET replica-priority $current_replica_priority"

    if is_empty "$REDIS_DEFAULT_PASSWORD"; then
        call_func_with_retry 3 5 execute_sub_command "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" "$redis_set_switchover_cmd"
    else
        call_func_with_retry 3 5 execute_sub_command "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$redis_set_switchover_cmd"
    fi
    # TODO: check the role in kernel before switchover
    master_name="$REDIS_COMPONENT_NAME"
    local success=false

    for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
        if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "26379" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
            success=true
            break
        fi
    done

    if [ "$success" = false ]; then
        echo "All Sentinel failover attempts failed."
        exit 1
    fi
    # TODO: check switchover result
    if is_empty "$REDIS_DEFAULT_PASSWORD"; then
        call_func_with_retry 3 5 execute_sub_command "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$REDIS_DEFAULT_PASSWORD" "$redis_set_recover_cmd"
    else
        call_func_with_retry 3 5 execute_sub_command "$KB_SWITCHOVER_CANDIDATE_FQDN" "6379" "$redis_set_recover_cmd"
    fi
}

switchoverWithoutCandidate() {
    # TODO: check the role in kernel before switchover
    master_name="$REDIS_COMPONENT_NAME"
    local success=false

    for sentinel_pod_fqdn in "${sentinel_pod_fqdn_list[@]}"; do
        if call_func_with_retry 3 5 execute_sub_command "$sentinel_pod_fqdn" "26379" "$SENTINEL_PASSWORD" "SENTINEL FAILOVER $master_name"; then
            success=true
            break
        fi
    done

    if [ "$success" = false ]; then
        echo "All Sentinel failover attempts failed."
        exit 1
    fi
    # TODO: check switchover result
}

if is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
    switchoverWithoutCandidate
else
    switchoverWithCandidate
fi
