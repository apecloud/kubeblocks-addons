#!/bin/bash

MAX_RETRIES=${MAX_RETRIES:-120}
RETRY_INTERVAL=${RETRY_INTERVAL:-5}
MAX_CONNECT_FAILURES=${MAX_CONNECT_FAILURES:-10}

redis_cmd="redis-cli $REDIS_CLI_TLS_CMD -h ${DP_DB_HOST} -p ${DP_DB_PORT}"
if [ -n "${REDIS_DEFAULT_PASSWORD}" ]; then
    redis_cmd="${redis_cmd} -a ${REDIS_DEFAULT_PASSWORD}"
fi

retry_count=0
connect_failures=0

while [ $retry_count -lt $MAX_RETRIES ]; do
    retry_count=$((retry_count + 1))
    cluster_info=$(${redis_cmd} CLUSTER INFO 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        connect_failures=$((connect_failures + 1))
        if [ $connect_failures -ge $MAX_CONNECT_FAILURES ]; then
            echo "ERROR: Redis cluster is not reachable after $MAX_CONNECT_FAILURES consecutive connection failures. Check host, port, and credentials." >&2
            exit 1
        fi
        echo "Redis cluster is not reachable (attempt $retry_count/$MAX_RETRIES, consecutive failures: $connect_failures/$MAX_CONNECT_FAILURES). Retrying in $RETRY_INTERVAL seconds..."
        sleep $RETRY_INTERVAL
        continue
    fi

    connect_failures=0

    state=$(echo "$cluster_info" | grep 'cluster_state:' | cut -d':' -f2 | tr -d '\r')
    if [[ "$state" == "ok" ]]; then
        echo "Redis cluster is ready."
        exit 0
    else
        echo "Redis cluster state is '$state' (attempt $retry_count/$MAX_RETRIES). Waiting for 'ok'. Retrying in $RETRY_INTERVAL seconds..."
        sleep $RETRY_INTERVAL
    fi
done

echo "ERROR: Redis cluster did not become ready after $MAX_RETRIES attempts ($((MAX_RETRIES * RETRY_INTERVAL)) seconds)." >&2
exit 1
