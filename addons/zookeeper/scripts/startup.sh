#!/bin/bash

myid_file="/bitnami/zookeeper/data/myid"

# Execute entrypoint as usual after obtaining ZOO_SERVER_ID, check ZOO_SERVER_ID in persistent volume via myid, if not present, set based on POD hostname
set_zookeeper_server_id() {
  if [[ -f "$myid_file" ]]; then
    ZOO_SERVER_ID="$(cat $myid_file)"
    export ZOO_SERVER_ID
  else
    SERVICE_ID="${CURRENT_POD_NAME##*-}"
    ZOO_SERVER_ID="$SERVICE_ID"
    export ZOO_SERVER_ID
    echo "$ZOO_SERVER_ID" > $myid_file
  fi
}

compare_version() {
  local op=$1
  local v1=$2
  local v2=$3
  local result

  result=$(echo -e "$v1\n$v2" | sort -V | head -n 1)

  case $op in
    gt) [[ "$result" != "$v1" ]];;
    le) [[ "$result" == "$v1" ]];;
    lt) [[ "$result" != "$v2" ]];;
    ge) [[ "$result" == "$v2" ]];;
  esac
}

set_jvm_configuration() {
  if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
      system_memory_in_mb=$(($(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)/1024/1024))
  elif [ -f /sys/fs/cgroup/memory.max ]; then
      system_memory_in_mb=$(($(cat /sys/fs/cgroup/memory.max)/1024/1024))
  else
      echo "ERROR: get memory limit failed, please check cgroup"
      exit 1
  fi

  # set max heap size based on the following
  # max(min(1/2 ram, 1024MB), min(1/4 ram, 8GB))
  half_system_memory_in_mb=$((system_memory_in_mb / 2))
  quarter_system_memory_in_mb=$((half_system_memory_in_mb / 2))
  if [ "$half_system_memory_in_mb" -gt "1024" ]; then
      half_system_memory_in_mb="1024"
  fi
  if [ "$quarter_system_memory_in_mb" -gt "8192" ]; then
      quarter_system_memory_in_mb="8192"
  fi
  if [ "$half_system_memory_in_mb" -gt "$quarter_system_memory_in_mb" ]; then
      max_heap_size_in_mb="$half_system_memory_in_mb"
  else
      max_heap_size_in_mb="$quarter_system_memory_in_mb"
  fi
  MAX_HEAP_SIZE="${max_heap_size_in_mb}M"

  export JVMFLAGS="$JVMFLAGS \
        -XX:+UseG1GC \
        -Xlog:gc:/opt/bitnami/zookeeper/logs/gc.log
        -Xlog:gc* \
        -XX:NewRatio=2 \
        -Xms$MAX_HEAP_SIZE -Xmx$MAX_HEAP_SIZE"
}

start() {
  set_zookeeper_server_id
  set_jvm_configuration
  exec "/entrypoint.sh" "/run.sh"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
start "$@"