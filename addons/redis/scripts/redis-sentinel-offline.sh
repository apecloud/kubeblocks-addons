#!/bin/bash
set -ex

declare -g redis_default_service_port=26379

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

      if [ $? -eq 0 ]; then
        echo "Successfully issued reset command on $host:$port"
      else
        echo "Failed to issue reset command on $host:$port"
      fi
    fi
  done
}
offline_sentinel