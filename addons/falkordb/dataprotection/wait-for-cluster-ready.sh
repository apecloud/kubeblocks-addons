#!/bin/bash

redis_cmd="redis-cli $REDIS_CLI_TLS_CMD -h ${DP_DB_HOST} -p ${DP_DB_PORT}"
if [ -n "${REDIS_DEFAULT_PASSWORD}" ]; then
    redis_cmd="${redis_cmd} -a ${REDIS_DEFAULT_PASSWORD}"
fi

while true; do
    cluster_info=$(${redis_cmd} CLUSTER INFO 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Redis cluster is not reachable yet. Retrying in 5 seconds..."
        sleep 5
        continue
    fi

    state=$(echo "$cluster_info" | grep 'cluster_state:' | cut -d':' -f2 | tr -d '\r')
    if [[ "$state" == "ok" ]]; then
        echo "Redis cluster is ready."
        break
    else
        echo "Redis cluster state is '$state'. Waiting for it to be 'ok'. Retrying in 5 seconds..."
        sleep 5
    fi
done