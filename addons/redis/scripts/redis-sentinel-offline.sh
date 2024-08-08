#!/bin/bash
set -ex

declare -g redis_default_service_port=26379
declare -A master_slave_counts

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

  local max_retries=3
  local retry_count=0
  local success=false
  local output=""
  while [ $retry_count -lt $max_retries ]; do
    if [ -n "$SENTINEL_PASSWORD" ]; then
      temp_output=$(redis-cli -h "$sentinel_leave_member_ip" -p "$redis_default_service_port" -a "$SENTINEL_PASSWORD" SENTINEL MASTERS 2>/dev/null || true)
    else
      temp_output=$(redis-cli -h "$sentinel_leave_member_ip" -p "$redis_default_service_port" SENTINEL MASTERS 2>/dev/null || true)
    fi
    if [ -n "$temp_output" ]; then
      disconnected=false
      while read -r line; do
          case "$line" in
              flags)
                  read -r master_flags
                  if [[ "$master_flags" == *"disconnected"* ]]; then
                      disconnected=true
                  fi
                  ;;
          esac
          master_flags=""
      done <<< "$temp_output"
      if [ "$disconnected" = true ]; then
          retry_count=$((retry_count + 1))
          echo "one or more masters are disconnected. $retry_count/$max_retries failed. retrying..."
      else
          echo "all masters are reachable."
          success=true
          output="$temp_output"
          break
      fi
    else
      retry_count=$((retry_count + 1))
      echo "timeout waiting for $host to become available $retry_count/$max_retries failed. retrying..."
    fi
    sleep 1
  done
  if [ "$success" = true ]; then
    echo "connected to the sentinel successfully after $retry_count retries"
  else
    echo "sentinel connect failed after $max_retries retries."
  fi
  if [[ -n "$output" ]]; then
      local master_name
      while read -r line; do
          case "$line" in
              name)
                  read -r master_name
                  ;;
          esac
          if [[ -n "$master_name" ]]; then
            echo "master name: $master_name"
            redis-cli -h "$sentinel_leave_member_ip" -p "$redis_default_service_port" -a "$SENTINEL_PASSWORD" SENTINEL REMOVE "$master_name"
          master_name=""
          fi
      done <<< "$output"
  else
      echo "unable to connect to redis sentinel, or no master nodes found."
  fi

  #sentinel reset *
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    host=$(echo "$sentinel_pod" | cut -d ':' -f 1)
    port=$(echo "$sentinel_pod" | cut -d ':' -f 2)
    sentinel_name="${host%%.*}"

    if [ -n "$port" ]; then
      redis_default_service_port="$port"
    fi
    #TODO:check if there is an ongoing HA switchover Before executing the reset command
    if [ "$sentinel_name" != "$sentinel_leave_member_name" ]; then
        retry_count=0
        max_retries=3
        success=false
        while [ $retry_count -lt $max_retries ]; do
            if [ -n "$SENTINEL_PASSWORD" ]; then
                if redis-cli -h "$host" -p "$redis_default_service_port" -a "$SENTINEL_PASSWORD" SENTINEL RESET "*" 2>/dev/null; then
                    echo "sentinel is resetting at $host on port $redis_default_service_port."
                    success=true
                    break
                fi
            else
                if redis-cli -h "$host" -p "$redis_default_service_port" SENTINEL RESET "*" 2>/dev/null; then
                    echo "sentinel is resetting at $host on port $redis_default_service_port."
                    success=true
                    break
                fi
            fi

            retry_count=$((retry_count + 1))
            echo "retry $retry_count/$max_retries for sentinel reset at $host failed. retrying..."
            sleep 1
        done

        if [ "$success" = true ]; then
            echo "connected to the sentinel successfully after $retry_count retries"
            sleep 3
        else
            echo "sentinel connect failed after $max_retries retries."
        fi
    fi
  done
  #Check that all the Sentinels agree about the number of Sentinels currently active
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
      host=$(echo "$sentinel_pod" | cut -d ':' -f 1)
      port=$(echo "$sentinel_pod" | cut -d ':' -f 2)
      sentinel_name="${host%%.*}"
      output=""

      if [ -n "$port" ]; then
        redis_default_service_port="$port"
      fi

      if [ "$sentinel_name" != "$sentinel_leave_member_name" ]; then
        max_retries=3
        retry_count=0
        success=false
        while [ $retry_count -lt $max_retries ]; do
          if [ -n "$SENTINEL_PASSWORD" ]; then
            temp_output=$(redis-cli -h "$host" -p "$port" -a "$SENTINEL_PASSWORD" SENTINEL MASTERS 2>/dev/null || true)
          else
            temp_output=$(redis-cli -h "$host" -p "$port" SENTINEL MASTERS 2>/dev/null || true)
          fi
          if [ -n "$temp_output" ]; then
            disconnected=false
            while read -r line; do
                case "$line" in
                    flags)
                        read -r master_flags
                        if [[ "$master_flags" == *"disconnected"* ]]; then
                            disconnected=true
                        fi
                        ;;
                esac
                master_flags=""
            done <<< "$temp_output"
            if [ "$disconnected" = true ]; then
                retry_count=$((retry_count + 1))
                echo "one or more masters are disconnected. $retry_count/$max_retries failed. retrying..."
            else
                echo "all masters are reachable."
                success=true
                output="$temp_output"
                break
            fi
          else
            retry_count=$((retry_count + 1))
            echo "timeout waiting for $host to become available $retry_count/$max_retries failed. retrying..."
          fi
          sleep 1
        done
        if [ "$success" = true ]; then
          echo "connected to the sentinel successfully after $retry_count retries"
        else
          echo "sentinel connect failed after $max_retries retries, it is either faulty or has already been shut down."
        fi
        if [[ -n "$output" ]]; then
            local master_name
            local num_other_sentinels
            while read -r line; do
                case "$line" in
                    name)
                        read -r master_name
                        ;;
                    num-other-sentinels)
                        read -r num_other_sentinels
                        ;;
                esac
                if [[ -n "$master_name" && -n "$num_other_sentinels" ]]; then
                  echo "master name: $master_name, num-other-sentinels: $num_other_sentinels"
                  if [[ -z "${master_slave_counts[$master_name]}" ]]; then
                    master_slave_counts[$master_name]=$num_other_sentinels
                  else
                    if [[ "${master_slave_counts[$master_name]}" -ne "$num_other_sentinels" ]]; then
                      echo "The number of slaves does not match the previous count; reset failed."
                      exit 1
                    fi
                  fi
                master_name=""
                num_other_sentinels=""
                fi
            done <<< "$output"
        else
            echo "unable to connect to redis sentinel, or no master nodes found."
        fi
      fi
  done
}

member_leave_sentinel