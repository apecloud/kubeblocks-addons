#!/bin/bash

set -ex

get_replica_host() {
    local id=$1
    
    if [ -z "${REPLICATION_ENDPOINT}" ]; then
        host="KB_${id}_HOSTNAME"
        echo "${!host}"
    else
        endpoints=$(eval echo "${REPLICATION_ENDPOINT}" | tr ',' '\n')
        for endpoint in ${endpoints}; do
            host=$(eval echo "${endpoint}" | cut -d ':' -f 1)
            ip=$(eval echo "${endpoint}" | cut -d ':' -f 2)
            hostId=$(eval echo "${host}" | grep -oE "[0-9]+\$")
            if [ "${id}" = "${hostId}" ]; then
                echo "${ip}"
                break
            fi
        done
    fi
}

generate_cluster_info() {
    local pod_name="${KB_POD_NAME:?missing pod name}"
    local cluster_members=""

    export MYSQL_PORT=${MYSQL_PORT:-3306}
    export MYSQL_CONSENSUS_PORT=${MYSQL_CONSENSUS_PORT:-13306}
    export KB_MYSQL_VOLUME_DIR=${KB_MYSQL_VOLUME_DIR:-/data/mysql/}
    export KB_MYSQL_CONF_FILE=${KB_MYSQL_CONF_FILE:-/opt/mysql/my.cnf}

    if [ -z "$KB_MYSQL_N" ]; then
        export KB_MYSQL_N=${KB_REPLICA_COUNT:?missing pod numbers}
    fi
    echo "KB_MYSQL_N=${KB_MYSQL_N}"

    if [ -z "$KB_MYSQL_CLUSTER_UID" ]; then
        export KB_MYSQL_CLUSTER_UID=${KB_CLUSTER_UID:?missing cluster uid}
    fi
    echo "KB_MYSQL_CLUSTER_UID=${KB_MYSQL_CLUSTER_UID}"

    for ((i = 0; i < KB_REPLICA_COUNT; i++)); do
        if [ $i -gt 0 ]; then
            cluster_members="${cluster_members};"
        fi

        host="$(get_replica_host ${i})"
        echo "${host:?missing member hostname}"
        cluster_members="${cluster_members}${host}:${MYSQL_CONSENSUS_PORT:-13306}"

        # compatiable with old version images
        export KB_MYSQL_${i}_HOSTNAME=${host}
    done
    export KB_MYSQL_CLUSTER_MEMBERS="${cluster_members}"

    export KB_MYSQL_CLUSTER_MEMBER_INDEX=${pod_name##*-};
    local pod_host=$(get_replica_host ${KB_MYSQL_CLUSTER_MEMBER_INDEX})
    export KB_MYSQL_CLUSTER_MEMBER_HOST=${pod_host:?missing current member hostname}

    if [ -n "$KB_LEADER" ]; then
        echo "KB_LEADER=${KB_LEADER}"

        local leader_index=${KB_LEADER##*-}
        local leader_host=$(get_replica_host ${leader_index})
        export KB_MYSQL_CLUSTER_LEADER_HOST=${leader_host:?missing leader hostname}

        # compatiable with old version images
        export KB_MSYQL_LEADER=${KB_LEADER}
    fi
}

rmdir /docker-entrypoint-initdb.d && mkdir -p /data/mysql/auditlog && mkdir -p /data/mysql/binlog && mkdir -p /data/mysql/docker-entrypoint-initdb.d && ln -s /data/mysql/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d;
generate_cluster_info
exec docker-entrypoint.sh
