#!/bin/bash

# shellcheck disable=SC2207

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -ex;
}

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

declare -g redis_default_service_port=26379
declare -A master_slave_counts
declare -g sentinel_leave_member_name
declare -g sentinel_leave_member_ip
declare -a sentinel_pod_list

redis_sentinel_member_get() {
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
  sentinel_pod_list=($(split "$KB_MEMBER_ADDRESSES" ","))
}

temp_output=""
redis_sentinel_get_masters() {
  local host="$1"
  local port="$2"
  if [ -n "$SENTINEL_PASSWORD" ]; then
    temp_output=$(redis-cli -h "$host" -p "$port" -a "$SENTINEL_PASSWORD" SENTINEL MASTERS 2>/dev/null || true)
  else
    temp_output=$(redis-cli -h "$host" -p "$port" SENTINEL MASTERS 2>/dev/null || true)
  fi
}

redis_sentinel_remove_monitor() {
  local max_retries=3
  local retry_count=0
  local success=false
  local output=""
  while [ $retry_count -lt $max_retries ]; do
    redis_sentinel_get_masters "$sentinel_leave_member_ip" "$redis_default_service_port" 
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
   sleep_when_ut_mode_false 1
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
        echo "sentinel no longer monitors $master_name"
        master_name=""
      fi
    done <<< "$output"
  else
    echo "unable to connect to redis sentinel, or no master nodes found."
  fi
}

redis_sentinel_reset_all() {
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
        sleep_when_ut_mode_false 1
      done

      if [ "$success" = true ]; then
        echo "connected to the sentinel successfully after $retry_count retries"
        sleep_when_ut_mode_false 3
      else
        echo "sentinel connect failed after $max_retries retries."
        exit 1
      fi
    fi
  done
  echo "all sentinels have been successfully reset."
}

#Check that all the Sentinels agree about the number of Sentinels currently active
check_all_sentinel_agreement() {
  for sentinel_pod in "${sentinel_pod_list[@]}"; do
    host=$(echo "$sentinel_pod" | cut -d ':' -f 1)
    port=$(echo "$sentinel_pod" | cut -d ':' -f 2)
    sentinel_name="${host%%.*}"
    echo "sentinel_pod $sentinel_pod"
    if [ -n "$port" ]; then
      redis_default_service_port="$port"
    fi

    if [ "$sentinel_name" != "$sentinel_leave_member_name" ]; then
      max_retries=3
      retry_count=0
      success=false
      output=""
      while [ $retry_count -lt $max_retries ]; do
        redis_sentinel_get_masters "$host" "$port"
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
        sleep_when_ut_mode_false 1
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
  echo "all the sentinels agree about the number of sentinels currently active"
}

# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

load_common_library
redis_sentinel_member_get
redis_sentinel_remove_monitor
redis_sentinel_reset_all
check_all_sentinel_agreement