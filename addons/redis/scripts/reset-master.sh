#!/bin/bash
if [ -z "${SENTINEL_POD_NAME_LIST}" ]; then
   exit 0
fi
${__SOURCED__:+false} : || return 0
master_name=${CUSTOM_SENTINEL_MASTER_NAME:-$REDIS_COMPONENT_NAME}
sentinel_service_port=${SENTINEL_SERVICE_PORT:-26379}
for sentinel_pod in $(echo ${SENTINEL_POD_NAME_LIST} | tr ',' '\n'); do
    echo "reset master in sentinel ${pod}..."
    fqdn="$sentinel_pod.$SENTINEL_HEADLESS_SERVICE_NAME.$CLUSTER_NAMESPACE.svc.cluster.local"
    if [ -n "${SENTINEL_PASSWORD}" ]; then
        redis-cli $REDIS_CLI_TLS_CMD -h $fqdn -p $sentinel_service_port -a ${SENTINEL_PASSWORD} sentinel reset ${master_name}
    else
        redis-cli $REDIS_CLI_TLS_CMD -h $fqdn -p $sentinel_service_port sentinel reset ${master_name}
    fi
    if [ $? -eq 0 ]; then
        echo "reset master in sentinel ${pod} succeeded"
        exit 0
    fi
done
echo "reset master in sentinel failed"
exit 1