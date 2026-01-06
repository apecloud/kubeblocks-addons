#!/bin/bash
if [ -z "${SENTINEL_POD_NAME_LIST}" ]; then
   exit 0
fi
tls_cmd=""
if [ "$TLS_ENABLED" == "true" ]; then
    tls_cmd="--tls --insecure"
fi
sentinel_service_port=${SENTINEL_SERVICE_PORT:-26379}
for sentinel_pod in $(echo ${SENTINEL_POD_NAME_LIST} | tr ',' '\n'); do
    echo "reset master in sentinel ${pod}..."
    fqdn="$sentinel_pod.$SENTINEL_HEADLESS_SERVICE_NAME.$CLUSTER_NAMESPACE.svc.cluster.local"
    if [ -n "${SENTINEL_PASSWORD}" ]; then
        redis-cli -h $fqdn -p $sentinel_service_port -a ${SENTINEL_PASSWORD} $tls_cmd sentinel reset ${REDIS_COMPONENT_NAME}
    else
        redis-cli -h $fqdn -p $sentinel_service_port $tls_cmd sentinel reset ${REDIS_COMPONENT_NAME}
    fi
    if [ $? -eq 0 ]; then
        echo "reset master in sentinel ${pod} succeeded"
        exit 0
    fi
done
echo "reset master in sentinel failed"
exit 1