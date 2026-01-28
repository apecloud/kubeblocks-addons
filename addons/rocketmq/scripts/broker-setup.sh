#!/bin/bash

source /scripts/util.sh

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

sync_file() {
    file_type=$1
    if [ "$file_type" == "topics.json" ]; then
        query_path="topicInfo"
    elif [ "$file_type" == "subscriptionGroup.json" ]; then
        query_path="subscriptionGroupInfo"
    else
        echo "Unknown file type: ${file_type}"
    fi

    if [ -f "${DATA_DIR}"/config/"${file_type}" ]; then
        return
    fi

    brokers=$(eval echo "${ALL_BROKER_FQDN}" | tr '@' '\n')
    if [ "$(echo "${brokers}" | wc -l)" -lt 2 ]; then
        return
    fi

    for broker in ${brokers}; do
        broker_name=$(echo "${broker}" | awk -F':' '{print $1}')
        fqdns_str=$(echo "${broker}" | awk -F':' '{print $NF}')
        if [ "$broker_name" == "${MY_COMP_NAME}" ]; then
            continue
        fi
        fqdns=$(eval echo "${fqdns_str}" | tr ',' '\n')
        for fqdn in ${fqdns}; do
            if ! curl -X GET -H 'Content-Type: application/json' http://"${fqdn}:${ROCKETMQ_AGENT}"/"${query_path}" > /tmp/"${file_type}" 2>/dev/null; then
                echo "Failed to fetch ${file_type} from ${fqdn}"
                continue
            else
                echo "Successfully fetched ${file_type} from ${fqdn}"
                break
            fi
        done

        if grep -q "dataVersion" /tmp/"${file_type}"; then
            if [ ! -d "${DATA_DIR}"/config ]; then
                mkdir -p "${DATA_DIR}"/config
            fi
            mv /tmp/"${file_type}" "${DATA_DIR}"/config/"${file_type}"
            return
        fi
    done
}

copy_log_config
init_broker
init_acl
sync_file "topics.json"
sync_file "subscriptionGroup.json"

export NAMESRV_ADDR=${ALL_NAMESRV_FQDN//,/:${NAMESRV_PORT};}:${NAMESRV_PORT}
if ! grep -q "NAMESRV_ADDR" ~/.bashrc; then
    echo "export NAMESRV_ADDR='${ALL_NAMESRV_FQDN//,/:${NAMESRV_PORT};}:${NAMESRV_PORT}'" >> ~/.bashrc
fi

calculate_heap_sizes
export HEAP_OPTS="-Xms${MAX_HEAP_SIZE} -Xmx${MAX_HEAP_SIZE} -Xmn${HEAP_NEWSIZE} -XX:MaxDirectMemorySize=${MAX_HEAP_SIZE}"

sh "${ROCKETMQ_HOME}"/bin/mqbroker -c "${DATA_DIR}"/broker.conf