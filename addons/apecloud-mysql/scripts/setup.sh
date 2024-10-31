#!/bin/bash

if [ -z "${__SOURCED__:+x}" ]; then
set -ex
fi

# MY_CLUSTER_NAME=clustername
# MY_COMP_NAME=componentname
# compose headless service name from cluster and component name
# return: clustername-componentname-headless
get_service_name() {
    cluster_name=${MY_CLUSTER_NAME:?missing cluster name}
    component_name=${MY_COMP_NAME:?missing component name}
    echo "${cluster_name}-${component_name}-headless"
}

get_cluster_members() {
    local cluster_members=""
    IFS=',' read -ra PODS <<< "$MY_POD_LIST"
    for pod in "${PODS[@]}"; do
        hostname=${pod}.$(get_service_name)
        cluster_members="${cluster_members};${hostname}:${MYSQL_CONSENSUS_PORT:-13306}"
    done
    echo "${cluster_members#;}"
}

get_pod_index() {
    local pod_name="${1:?missing pod name}"
    local pod_index=0

    IFS=',' read -ra PODS <<< "$MY_POD_LIST"
    for pod in "${PODS[@]}"; do
        if [ "$pod" = "$pod_name" ]; then
            break
        fi
        ((pod_index++))
    done
    
    echo "$pod_index"
}

generate_cluster_info() {
    local pod_name="${MY_POD_NAME:?missing pod name}"
    local cluster_members=""
    local service_name=$(get_service_name)

    export MYSQL_PORT=${MYSQL_PORT:-3306}
    export MYSQL_CONSENSUS_PORT=${MYSQL_CONSENSUS_PORT:-13306}
    export KB_MYSQL_VOLUME_DIR=${KB_MYSQL_VOLUME_DIR:-/data/mysql/}
    export KB_MYSQL_CONF_FILE=${KB_MYSQL_CONF_FILE:-/opt/mysql/my.cnf}

    if [ -z "$KB_MYSQL_N" ]; then
        export KB_MYSQL_N=${MY_COMP_REPLICAS:?missing pod numbers}
    fi
    echo "KB_MYSQL_N=${KB_MYSQL_N}"

    if [ -z "$KB_MYSQL_CLUSTER_UID" ]; then
        export KB_MYSQL_CLUSTER_UID=${MY_CLUSTER_UID:?missing cluster uid}
    fi
    echo "KB_MYSQL_CLUSTER_UID=${KB_MYSQL_CLUSTER_UID}"

    export KB_MYSQL_CLUSTER_MEMBERS=`get_cluster_members`
    echo "${KB_MYSQL_CLUSTER_MEMBERS:?missing cluster members}"

    export KB_MYSQL_CLUSTER_MEMBER_INDEX=`get_pod_index $pod_name`
    local pod_host=${pod_name}.${service_name}
    export KB_MYSQL_CLUSTER_MEMBER_HOST=${pod_host:?missing current member hostname}

    if [ -n "$MYSQL_LEADER_POD_NAME" ]; then
        echo "MYSQL_LEADER_POD_NAME=${MYSQL_LEADER_POD_NAME}"

        local leader_host=$MYSQL_LEADER_POD_NAME.${service_name}
        export KB_MYSQL_CLUSTER_LEADER_HOST=${leader_host:?missing leader hostname}

        # compatiable with old version images
        export KB_MSYQL_LEADER=${MYSQL_LEADER_POD_NAME}
    fi
}

# if test by shellspec include, just return 0
if [ "${__SOURCED__:+x}" ]; then
  return 0
fi

rmdir /docker-entrypoint-initdb.d && mkdir -p ${KB_MYSQL_VOLUME_DIR}/auditlog && mkdir -p ${KB_MYSQL_VOLUME_DIR}/binlog && mkdir -p ${KB_MYSQL_VOLUME_DIR}/docker-entrypoint-initdb.d && ln -s ${KB_MYSQL_VOLUME_DIR}/docker-entrypoint-initdb.d /docker-entrypoint-initdb.d;
generate_cluster_info
exec docker-entrypoint.sh
