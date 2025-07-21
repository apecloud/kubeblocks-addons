#!/bin/bash
if [ -z "${SENTINEL_POD_NAME_LIST}" ]; then
   exit 0
fi
for sentinel_pod in $(echo ${SENTINEL_POD_NAME_LIST} | tr ',' '\n'); do
    echo "reset master in sentinel ${pod}..."
    fqdn="$sentinel_pod.$SENTINEL_HEADLESS_SERVICE_NAME.$KB_NAMESPACE.svc.cluster.local"
    redis-cli -h $fqdn -p 26379 -a ${SENTINEL_PASSWORD} sentinel reset ${KB_CLUSTER_COMP_NAME}
    if [ $? -eq 0 ]; then
        echo "reset master in sentinel ${pod} succeeded"
        exit 0
    fi
done
echo "reset master in sentinel failed"
exit 1