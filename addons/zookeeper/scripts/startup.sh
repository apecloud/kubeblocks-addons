#!/bin/bash

# Execute entrypoint as usual after obtaining ZOO_SERVER_ID
# check ZOO_SERVER_ID in persistent volume via myid
# if not present, set based on POD hostname
if [[ -f "/bitnami/zookeeper/data/myid" ]]; then
  export ZOO_SERVER_ID="$(cat /bitnami/zookeeper/data/myid)"
else
  SERVICE_ID=${CURRENT_POD_NAME##*-}
  export ZOO_SERVER_ID=$SERVICE_ID
  echo $ZOO_SERVER_ID > /bitnami/zookeeper/data/myid
fi

function version_gt() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" != "$1"; }
function version_le() { test "$(echo "$@" | tr " " "\n" | sort -V | head -n 1)" == "$1"; }
function version_lt() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" != "$1"; }
function version_ge() { test "$(echo "$@" | tr " " "\n" | sort -rV | head -n 1)" == "$1"; }

function set_jvm_configuration() {
  if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
      system_memory_in_mb=$(($(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)/1024/1024))
  elif [ -f /sys/fs/cgroup/memory.max ]; then
      mem_limit=$(cat /sys/fs/cgroup/memory.max)
      if [ "$mem_limit" = "max" ]; then
          system_memory_in_mb=$(free -m| sed -n '2p' | awk '{print $2}')
      else
          system_memory_in_mb=$(($mem_limit/1024/1024))
      fi
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

if [ -z "${ZOOKEEPER_IMAGE_VERSION}" ] ||  version_lt "3.6.0" "${ZOOKEEPER_IMAGE_VERSION%%-*}"  ; then
  scripts_path="/opt/bitnami/scripts/zookeeper"
else
  scripts_path=""
fi

set_jvm_configuration
exec ${scripts_path}/entrypoint.sh ${scripts_path}/run.sh