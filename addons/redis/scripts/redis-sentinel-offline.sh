#!/bin/bash
set -ex

declare -g redis_default_service_port=26379

wait_for_connectivity() {
  local host=$1
  local port=$2
  local password=$3
  local timeout=600
  local start_time
  local current_time
  start_time=$(date +%s)
  echo "Checking connectivity to $host on port $port using redis-cli..."
  while true; do
    current_time=$(date +%s)
    if [ $((current_time - start_time)) -gt $timeout ]; then
      echo "Timeout waiting for $host to become available."
      exit 1
    fi

    # Send PING and check for PONG response
    if [ -n "$password" ]; then
      if redis-cli -h "$host" -p "$port" -a "$password" PING | grep -q "PONG"; then
        echo "$host is reachable on port $port."
        break
      fi
    else
      if redis-cli -h "$host" -p "$port" PING | grep -q "PONG"; then
        echo "$host is reachable on port $port."
        break
      fi
    fi

    sleep 5
  done
}

member_leave_sentinel() {
  if [ -z "$KB_LEAVE_MEMBER_POD_IP" ]; then
    echo "Error: Required environment variable KB_LEAVE_MEMBER_POD_IP is not set."
    exit 1
  fi

  if [ -z "$KB_LEAVE_MEMBER_POD_NAME" ]; then
    echo "Error: Required environment variable KB_LEAVE_MEMBER_POD_NAME is not set."
    exit 1
  fi

  if [ -z "$KB_MEMBER_ADDRESSES" ]; then
    echo "Error: Required environment variable KB_MEMBER_ADDRESSES is not set."
    exit 1
  fi

  sentinel_leave_member_name=$KB_LEAVE_MEMBER_POD_NAME
  sentinel_leave_member_ip=$KB_LEAVE_MEMBER_POD_IP

  old_ifs="$IFS"
  IFS=','
  set -f
  read -ra sentinel_pod_list <<< "${KB_MEMBER_ADDRESSES}"
  set +f
  IFS="$old_ifs"

  if [ -n "$SENTINEL_PASSWORD" ]; then
    wait_for_connectivity "$sentinel_leave_member_ip" "$redis_default_service_port" "$SENTINEL_PASSWORD"
    redis-cli -h "$sentinel_leave_member_ip" -p "$redis_default_service_port" -a "$SENTINEL_PASSWORD" shutdown
  else
    wait_for_connectivity "$sentinel_leave_member_ip" "$redis_default_service_port"
    redis-cli -h "$sentinel_leave_member_ip" -p "$redis_default_service_port" shutdown
  fi

  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    host=$(echo "$sentinel_pod" | cut -d ':' -f 1)
    port=$(echo "$sentinel_pod" | cut -d ':' -f 2)
    sentinel_name="${host%%.*}"

    if [ -n "$port" ]; then
      redis_default_service_port="$port"
    fi
    #TODO:check if there is an ongoing HA switchover Before executing the reset command
    if [ "$sentinel_name" != "$sentinel_leave_member_name" ]; then
      if [ -n "$SENTINEL_PASSWORD" ]; then
        wait_for_connectivity "$host" "$redis_default_service_port" "$SENTINEL_PASSWORD"
        redis-cli -h "$host" -p "$redis_default_service_port" -a "$SENTINEL_PASSWORD" sentinel reset "*"
      else
        wait_for_connectivity "$host" "$redis_default_service_port"
        redis-cli -h "$host" -p "$redis_default_service_port" sentinel reset "*"
      fi
    fi
  done
  #TODO: Check that all the Sentinels agree about the number of Sentinels currently active
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
      host=$(echo "$sentinel_pod" | cut -d ':' -f 1)
      port=$(echo "$sentinel_pod" | cut -d ':' -f 2)
      sentinel_name="${host%%.*}"

      if [ -n "$port" ]; then
        redis_default_service_port="$port"
      fi

      if [ "$sentinel_name" != "$sentinel_leave_member_name" ]; then
        if [ -n "$SENTINEL_PASSWORD" ]; then
          output=$(redis-cli -h "$host" -p "$redis_default_service_port" -a "$SENTINEL_PASSWORD" sentinel masters)
        else
          output=$(redis-cli -h "$host" -p "$redis_default_service_port" sentinel masters)
        fi
        if [[ -n "$output" ]]; then
            master_name=""
            num_slaves=""
            while read -r line; do
                case "$line" in
                    name)
                        read -r master_name
                        ;;
                    num-slaves)
                        read -r num_slaves
                        ;;
                esac
                if [[ -n "$master_name" && -n "$num_slaves" ]]; then
                  echo "Master Name: $master_name, num-slaves: $num_slaves"
                  if [[ -z "${master_slave_counts[$master_name]}" ]]; then
                    master_slave_counts[$master_name]=$num_slaves
                  else
                    if [[ "${master_slave_counts[$master_name]}" -ne "$num_slaves" ]]; then
                      echo "The number of slaves does not match the previous count; reset failed."
                      exit 1
                    fi
                  fi
                master_name=""
                num_slaves=""
                fi
            done <<< "$output"
        else
            echo "unable to connect to Redis Sentinel, or no master nodes found."
        fi
      fi
    done
}

member_leave_sentinel