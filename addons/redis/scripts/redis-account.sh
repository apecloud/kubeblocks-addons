#!/bin/bash

set -e

function do_acl_command() {
    local hosts=$1
    IFS=',' read -ra HOSTS <<<"$hosts"
    local service_port=$2
    local user=$3
    local password=$4
    local success_count=0

    for host in "${HOSTS[@]}"; do
        # in case, the host is like this: apple-7bff57f594-shard-b8p-1.apple-7bff57f594-shard-b8p-headless.kubeblocks-cloud-ns.svc.cluster.local,apple-7bff57f594-shard-9x9-0.apple-7bff57f594-shard-9x9-headless.kubeblocks-cloud-ns.svc.cluster.local,apple-7bff57f594-shard-8bf-1.apple-7bff57f594-shard-8bf-headless.kubeblocks-cloud-ns.svc.cluster.local
        # in case of fixed ip mode, the host is like this: 10.96.180.100:6379@1 10.96.180.100:6379@2
        # we need to remove the @1 or @2 and remove the port
        host=$(echo "$host" | sed 's/@[0-9]*//g' | sed 's/:[0-9]*/ /g')
        cmd="redis-cli -h $host -p $service_port --user $user -a $password"
        if [ -n "$ACL_COMMAND" ]; then
            echo "DO ACL COMMAND FOR HOST: $host"
            $cmd $ACL_COMMAND
            if [ $? -ne 0 ]; then
                echo "DO ACL COMMAND FOR HOST: $host FAILED"
                exit 1
            fi
        else
            echo "ACL_COMMAND IS EMPTY, SKIP ACL COMMAND"
        fi
        echo "DO ACL SAVE FOR HOST: $host"
        $cmd ACL SAVE
        if [ $? -ne 0 ]; then
            echo "DO ACL SAVE FOR HOST: $host FAILED"
            exit 1
        fi
        success_count=$((success_count + 1))
    done

    create_post_check "$success_count"
}

function env_pre_check() {
    if [ -z "$ACL_COMMAND" ]; then
        echo "ACL_COMMAND is empty, skip ACL operation"
        exit 1
    fi

    if [ -z "$SERVICE_PORT" ]; then
        echo "SERVICE_PORT is empty, skip ACL operation"
        exit 1
    fi

    if [ -z "$REDIS_DEFAULT_USER" ]; then
        echo "REDIS_DEFAULT_USER is empty, skip ACL operation"
        exit 1
    fi

    if [ -z "$REDIS_DEFAULT_PASSWORD" ]; then
        echo "REDIS_DEFAULT_PASSWORD is empty, skip ACL operation"
        exit 1
    fi

    # cluster mode don't have KB_POD_LIST, but have REDIS_POD_FQDN_LIST and get hosts from redis-cli
    if [ "$SHARD_MODE" != "TRUE" ] && [ -z "$REDIS_POD_FQDN_LIST" ]; then
        echo "REDIS_POD_FQDN_LIST is empty, skip ACL operation"
        exit 0
    fi

    if [ "$SHARD_MODE" == "TRUE" ] && [ -z "$CURRENT_POD_NAME" ]; then
        echo "CURRENT_POD_NAME is empty, skip ACL operation"
        exit 0
    fi

    if [ "$SHARD_MODE" == "TRUE" ] && [ -z "$CURRENT_SHARD_COMPONENT_NAME" ]; then
        echo "CURRENT_SHARD_COMPONENT_NAME is empty, skip ACL operation"
        exit 0
    fi
    
    if [ "$SHARD_MODE" == "TRUE" ] && [ -z "$CLUSTER_NAMESPACE" ]; then
        echo "CLUSTER_NAMESPACE is empty, skip ACL operation"
        exit 0
    fi

    if [ "$SHARD_MODE" == "TRUE" ] && [ -z "$CLUSTER_DOMAIN" ]; then
        echo "CLUSTER_DOMAIN is empty, skip ACL operation"
        exit 0
    fi
    
}

function create_post_check() {
    local success_count=$1
    if [ "$success_count" -eq $REPLICAS ]; then
        echo "DO ACL COMMAND FOR ALL HOSTS SUCCESS"
        exit 0
    else
        echo "Need to create $REPLICAS hosts account, but only $success_count hosts account are created"
        exit 1
    fi
}

function get_cluster_host_list() {
    host_list=$(redis-cli -c -h "$CURRENT_POD_NAME.$CURRENT_SHARD_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN" \
        -p $SERVICE_PORT \
        --user $REDIS_DEFAULT_USER \
        -a $REDIS_DEFAULT_PASSWORD \
        CLUSTER NODES |
        grep -v "fail" |
        grep -v "noaddr" |
        awk '{print $2}' |
        cut -d ',' -f2 |
        paste -sd,)
}

function main() {
    env_pre_check

    if [ "$SHARD_MODE" = "TRUE" ]; then
        get_cluster_host_list
    else
        host_list="$REDIS_POD_FQDN_LIST"
    fi
    do_acl_command "$host_list" "$SERVICE_PORT" "$REDIS_DEFAULT_USER" "$REDIS_DEFAULT_PASSWORD"
}

main
