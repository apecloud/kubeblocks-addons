#!/bin/bash

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

# Example usage:
# group_similar_ips "192.168.0.1,192.168.0.2,192.168.10.1,192.168.10.2"
# Output: 192.168.0.*,192.168.10.*
group_similar_ips() {
    # Store input IP string
    local ip_string="$1"

    # 1. Split IPs by comma into lines
    # 2. Extract first three octets of each IP
    # 3. Sort and group by first three octets, then add wildcard
    echo "$ip_string" |
        # Convert comma separator to newlines
        tr ',' '\n' |
        # Extract first three octets of each IP
        sed 's/\([0-9]\+\.[0-9]\+\.[0-9]\+\)\.[0-9]\+/\1/' |
        # Sort and remove duplicates
        sort -u |
        # Append wildcard
        sed 's/$/.*/' |
        # Convert newlines back to comma separator
        paste -sd ','
}

calculate_heap_sizes() {
    system_memory_in_mb=$(free -m| sed -n '2p' | awk '{print $2}')
    if [ -f /sys/fs/cgroup/memory/memory.limit_in_bytes ]; then
        system_memory_in_mb_in_docker=$(($(cat /sys/fs/cgroup/memory/memory.limit_in_bytes)/1024/1024))
    elif [ -f /sys/fs/cgroup/memory.max ]; then
        system_memory_in_mb_in_docker=$(($(cat /sys/fs/cgroup/memory.max)/1024/1024))
    else
        error_exit "Can not get memory, please check cgroup"
    fi
    if [ $system_memory_in_mb_in_docker -lt "$system_memory_in_mb" ];then
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
}

copy_log_config() {
    if [ ! -f "${ROCKETMQ_HOME}"/conf/logback_broker.xml ]; then
        cp -f /kb-config/logback_broker.xml "${ROCKETMQ_HOME}"/conf
        cp -f /kb-config/logback_tools.xml "${ROCKETMQ_HOME}"/conf
    fi
}

init_broker() {
    if [ ! -f "${DATA_DIR}"/broker.conf ]; then
        cp -f /kb-config/broker.conf "${DATA_DIR}"/broker.conf
        chmod +w "${DATA_DIR}"/broker.conf

        index=$(echo "${MY_POD_NAME}" | awk -F'-' '{print $NF}')
        if [ "$ENABLE_DLEDGER" = "true" ]; then
            printf "\ndLegerGroup=%s" "${MY_COMP_NAME}" >> "${DATA_DIR}"/broker.conf
            printf "\ndLegerSelfId=n%s" "${index}" >> "${DATA_DIR}"/broker.conf
            replicas=$(eval echo "${MY_POD_LIST}" | tr ',' '\n')
            dLegerPeers=""
            for replica in ${replicas}; do
                replica_index=$(echo "${replica}" | awk -F'-' '{print $NF}')
                replica_host="n${replica_index}-${replica}.${MY_CLUSTER_COMP_NAME}-headless:${DLEDGER_PORT}"
                if [ -z "$dLegerPeers" ]; then
                    dLegerPeers=$replica_host
                else
                    dLegerPeers="$dLegerPeers;$replica_host"
                fi
            done
            printf "\ndLegerPeers=%s" "$dLegerPeers" >> "${DATA_DIR}"/broker.conf
        else
            printf "\nbrokerId=%s" "${index}" >> "${DATA_DIR}"/broker.conf
            if [ "$index" -eq 0 ]; then
                printf "\nbrokerRole=%s" "ASYNC_MASTER" >> "${DATA_DIR}"/broker.conf
            else
                printf "\nbrokerRole=%s" "SLAVE" >> "${DATA_DIR}"/broker.conf
            fi
        fi
    else
        if grep -q "brokerIP1" "${DATA_DIR}"/broker.conf; then
            sed -i "s/brokerIP1=.*/brokerIP1=${MY_POD_IP}/" "${DATA_DIR}"/broker.conf
        fi
        if grep -q "brokerIP2" "${DATA_DIR}"/broker.conf; then
            sed -i "s/brokerIP2=.*/brokerIP2=${MY_POD_IP}/" "${DATA_DIR}"/broker.conf
        fi
    fi
}

init_acl() {
    if [ ! -f "${ROCKETMQ_HOME}"/conf/plain_acl.yml ]; then
        cp -f /kb-config/plain_acl.yml "${ROCKETMQ_HOME}"/conf
        chmod +w "${ROCKETMQ_HOME}"/conf/plain_acl.yml

        if [ "$ENABLE_ACL" = "true" ]; then
            brokers=$(eval echo "${ALL_BROKER_FQDN}" | tr '@' '\n')
            all_ips=""
            for broker in ${brokers}; do
              fqdns_str=$(echo "${broker}" | awk -F':' '{print $NF}')
              fqdns=$(eval echo "${fqdns_str}" | tr ',' '\n')
              for fqdn in ${fqdns}; do
                ip=$(get_remote_ip "$fqdn")
                if [ -z "$ip" ]; then
                    echo "Failed to get IP for $fqdn"
                    rm -f "${ROCKETMQ_HOME}"/conf/plain_acl.yml
                    exit 1
                fi

                if [ -z "$all_ips" ]; then
                    all_ips=$ip
                else
                    all_ips="$all_ips,$ip"
                fi
              done
            done

            ip_groups=$(group_similar_ips "$all_ips")
            ip_group_prefix=$(eval echo "${ip_groups}" | tr ',' '\n')
            for prefix in ${ip_group_prefix}; do
              sed -i "/^globalWhiteRemoteAddresses:/a\  - ${prefix}" "${ROCKETMQ_HOME}"/conf/plain_acl.yml
            done

            sed -i "/^accounts:/a\  - accessKey: ${ROCKETMQ_USER}\n    secretKey: ${ROCKETMQ_PASSWORD}\n    admin: true" "${ROCKETMQ_HOME}"/conf/plain_acl.yml
        fi
    fi
}

copy_log_config
init_broker
init_acl

export NAMESRV_ADDR=${ALL_NAMESRV_FQDN//,/:${NAMESRV_PORT};}:${NAMESRV_PORT}
if ! grep -q "NAMESRV_ADDR" ~/.bashrc; then
    echo "export NAMESRV_ADDR='${ALL_NAMESRV_FQDN//,/:${NAMESRV_PORT};}:${NAMESRV_PORT}'" >> ~/.bashrc
fi

calculate_heap_sizes
export HEAP_OPTS="-server -Xms${MAX_HEAP_SIZE} -Xmx${MAX_HEAP_SIZE} -Xmn${HEAP_NEWSIZE} -XX:MaxDirectMemorySize=${MAX_HEAP_SIZE}"

sh "${ROCKETMQ_HOME}"/bin/mqbroker -c "${DATA_DIR}"/broker.conf