#!/bin/bash
set -ex

declare -g redis_default_service_port=26379
declare -A master_slave_counts

offline_sentinel() {

  if [ -z "$KB_LEAVE_MEMBER_POD_IP" ]; then
    echo "Error: Required environment variable KB_LEAVE_MEMBER_POD_IP is not set."
    exit 1
  fi

  if [ -z "$KB_MEMBER_ADDRESSES" ]; then
    echo "Error: Required environment variable KB_MEMBER_ADDRESSES is not set."
    exit 1
  fi

  sentinel_leave_member_name=$KB_LEAVE_MEMBER_POD_NAME

  old_ifs="$IFS"
  IFS=','
  set -f
  read -ra sentinel_pod_list <<< "${KB_MEMBER_ADDRESSES}"
  set +f
  IFS="$old_ifs"
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    host=$(echo "$sentinel_pod" | cut -d ':' -f 1)
    port=$(echo "$sentinel_pod" | cut -d ':' -f 2)
    sentinel_name="${host%%.*}"

    if [ -z "$port" ]; then
      port="$redis_default_service_port"
    fi

    if [ "$sentinel_name" != "$sentinel_leave_member_name" ]; then
      if [ -n "$SENTINEL_PASSWORD" ]; then
        redis-cli -h "$host" -p "$port" -a "$SENTINEL_PASSWORD" sentinel reset "*"
      else
        redis-cli -h "$host" -p "$port" sentinel reset "*"
      fi
      if [ -n "$SENTINEL_PASSWORD" ]; then
        output=$(redis-cli -h "$host" -p "$port" -a "$SENTINEL_PASSWORD" sentinel masters)
      else
        output=$(redis-cli -h "$host" -p "$port" sentinel masters)
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
  echo "reset successful"
}
offline_sentinel