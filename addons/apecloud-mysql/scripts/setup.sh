#!/bin/bash

set -ex

get_hostname_suffix() {
    IFS='.' read -ra fields <<< "$KB_POD_FQDN"
    if [ "${#fields[@]}" -gt "2" ]; then
        echo "${fields[1]}"
    fi
}

generate_cluster_info() {
    local pod_name="${KB_POD_NAME:?missing pod name}"
    local cluster_members=""
    local hostname_suffix=$(get_hostname_suffix)

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

    IFS=',' read -ra PODS <<< "$KB_POD_LIST"
    for pod in "${PODS[@]}"; do
        hostname=${pod}.${hostname_suffix}
        echo "${hostname:?missing member hostname}"
        cluster_members="${cluster_members};${hostname}:${MYSQL_CONSENSUS_PORT:-13306}"
    done

    export KB_MYSQL_CLUSTER_MEMBERS="${cluster_members#;}"
    echo "${KB_MYSQL_CLUSTER_MEMBERS:?missing cluster members}"

    export KB_MYSQL_CLUSTER_MEMBER_INDEX=${pod_name##*-};
    local pod_host=${pod_name}.${hostname_suffix}
    export KB_MYSQL_CLUSTER_MEMBER_HOST=${pod_host:?missing current member hostname}

    if [ -n "$KB_LEADER" ]; then
        echo "KB_LEADER=${KB_LEADER}"

        local leader_index=${KB_LEADER##*-}
        local leader_host=$KB_LEADER.${hostname_suffix}
        export KB_MYSQL_CLUSTER_LEADER_HOST=${leader_host:?missing leader hostname}

        # compatiable with old version images
        export KB_MSYQL_LEADER=${KB_LEADER}
    fi
}

rmdir /docker-entrypoint-initdb.d && mkdir -p /data/mysql/auditlog && mkdir -p /data/mysql/binlog && mkdir -p /data/mysql/docker-entrypoint-initdb.d && ln -s /data/mysql/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d;
generate_cluster_info
exec docker-entrypoint.sh
