#!/bin/bash
set -ex

generate_cluster_info() {
    local pod_name="${KB_POD_NAME:?missing pod name}"
    local cluster_members=""

    echo "KB_MYSQL_N=${KB_MYSQL_N}"
    for ((i = 0; i < KB_MYSQL_N; i++)); do
        if [ $i -gt 0 ]; then
            cluster_members="${cluster_members};"
        fi

        host="KB_${i}_HOSTNAME"
        echo "${host}=${!host:?missing member hostname}"
        cluster_members="${cluster_members}${!host}:${MYSQL_CONSENSUS_PORT:-13306}"

        # compatiable with old version images
        export KB_MYSQL_${i}_HOSTNAME=${!host}
    done
    export KB_MYSQL_CLUSTER_MEMBERS="${cluster_members}"

    export KB_MYSQL_CLUSTER_MEMBER_INDEX=${pod_name##*-};
    local pod_host="KB_${KB_MYSQL_CLUSTER_MEMBER_INDEX}_HOSTNAME"
    export KB_MYSQL_CLUSTER_MEMBER_HOST=${!pod_host:?missing current member hostname}

    if [ -n "$KB_LEADER" ]; then
        echo "KB_LEADER=${KB_LEADER}"

        local leader_index=${KB_LEADER##*-}
        local leader_host="KB_${leader_index}_HOSTNAME"
        export KB_MYSQL_CLUSTER_LEADER_HOST=${!leader_host:?missing leader hostname}

        # compatiable with old version images
        export KB_MSYQL_LEADER=${KB_LEADER}
    fi
}

rmdir /docker-entrypoint-initdb.d && mkdir -p /data/mysql/auditlog && mkdir -p /data/mysql/binlog && mkdir -p /data/mysql/docker-entrypoint-initdb.d && ln -s /data/mysql/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d;
generate_cluster_info
exec docker-entrypoint.sh
