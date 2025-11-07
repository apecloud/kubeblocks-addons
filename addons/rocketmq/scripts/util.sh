#!/bin/bash

calculate_heap_sizes() {
    system_memory_in_mb=$(free -m| sed -n '2p' | awk '{print $2}')
    if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        system_memory_in_mb_in_docker=$(($(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)/1024/1024))
    elif [ -f /sys/fs/cgroup/memory.max ]; then
        system_memory_in_mb_in_docker=$(($(cat /sys/fs/cgroup/memory.max)/1024/1024))
    else
        error_exit "Can not get memory, please check cgroup"
    fi
    if [ "$system_memory_in_mb_in_docker" -lt "$system_memory_in_mb" ];then
      system_memory_in_mb=$system_memory_in_mb_in_docker
    fi

    system_cpu_cores=$(grep -E -c 'processor([[:space:]]+):.*' /proc/cpuinfo)
    if [ -f /sys/fs/cgroup/cpu/cpu.cfs_quota_us ]; then
        system_cpu_cores_in_docker=$(($(cat /sys/fs/cgroup/cpu/cpu.cfs_quota_us)/$(cat /sys/fs/cgroup/cpu/cpu.cfs_period_us)))
    elif [ -f /sys/fs/cgroup/cpu.max ]; then
        QUOTA=$(cut -d ' ' -f 1 /sys/fs/cgroup/cpu.max)
        PERIOD=$(cut -d ' ' -f 2 /sys/fs/cgroup/cpu.max)
        if [ "$QUOTA" == "max" ]; then # no limit, see https://docs.kernel.org/admin-guide/cgroup-v2.html#cgroup-v2-cpu
          system_cpu_cores_in_docker=$system_cpu_cores
        else
          system_cpu_cores_in_docker=$((QUOTA/PERIOD))
        fi
    else
        error_exit "Can not get cpu, please check cgroup"
    fi
    if [ "$system_cpu_cores_in_docker" -lt "$system_cpu_cores" ] && [ "$system_cpu_cores_in_docker" -ne 0 ]; then
        system_cpu_cores=$system_cpu_cores_in_docker
    fi

    # some systems like the raspberry pi don't report cores, use at least 1
    if [ "$system_cpu_cores" -lt "1" ]
    then
        system_cpu_cores="1"
    fi

    # set max heap size based on the following
    # max(min(1/2 ram, 1024MB), min(1/4 ram, 8GB))
    # calculate 1/2 ram and cap to 1024MB
    # calculate 1/4 ram and cap to 8192MB
    # pick the max
    half_system_memory_in_mb=$((system_memory_in_mb / 2))
    quarter_system_memory_in_mb=$((half_system_memory_in_mb / 2))
    if [ "$half_system_memory_in_mb" -gt "1024" ]
    then
        half_system_memory_in_mb="1024"
    fi
    if [ "$quarter_system_memory_in_mb" -gt "8192" ]
    then
        quarter_system_memory_in_mb="8192"
    fi
    if [ "$half_system_memory_in_mb" -gt "$quarter_system_memory_in_mb" ]
    then
        max_heap_size_in_mb="$half_system_memory_in_mb"
    else
        max_heap_size_in_mb="$quarter_system_memory_in_mb"
    fi
    MAX_HEAP_SIZE="${max_heap_size_in_mb}M"

    # Young gen: min(max_sensible_per_modern_cpu_core * num_cores, 1/4 * heap size)
    max_sensible_yg_per_core_in_mb="100"
    max_sensible_yg_in_mb=$((max_sensible_yg_per_core_in_mb * system_cpu_cores))

    desired_yg_in_mb=$((max_heap_size_in_mb / 4))

    if [ "$desired_yg_in_mb" -gt "$max_sensible_yg_in_mb" ]
    then
        HEAP_NEWSIZE="${max_sensible_yg_in_mb}M"
    else
        HEAP_NEWSIZE="${desired_yg_in_mb}M"
    fi
    export MAX_HEAP_SIZE
    export HEAP_NEWSIZE
}

get_remote_ip() {
    host="$1"
    local retry_counter=0
    local max_retry=60

    while [ $retry_counter -lt $max_retry ]; do
        ip=$(getent hosts "$host" | awk '{ print $1 }')
        if [ -n "$ip" ]; then
            echo "$ip"
            return
        else
            retry_counter=$((retry_counter+1))
            sleep 1
        fi
    done

    exit 1
}