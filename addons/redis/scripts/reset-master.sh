#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -e;
}

sentinel_service_port=${SENTINEL_SERVICE_PORT:-26379}

reset_master_in_sentinels() {
  if [ -z "${SENTINEL_POD_NAME_LIST}" ]; then
    exit 0
  fi
  # shellcheck disable=SC2086
  for sentinel_pod in $(echo ${SENTINEL_POD_NAME_LIST} | tr ',' '\n'); do
    echo "reset master in sentinel ${sentinel_pod}..."
    fqdn="$sentinel_pod.$SENTINEL_HEADLESS_SERVICE_NAME.$CLUSTER_NAMESPACE.svc.cluster.local"
    # shellcheck disable=SC2086
    if [ -n "${SENTINEL_PASSWORD}" ]; then
      redis-cli $REDIS_CLI_TLS_CMD -h $fqdn -p $sentinel_service_port -a ${SENTINEL_PASSWORD} sentinel reset ${REDIS_COMPONENT_NAME}
    else
      redis-cli $REDIS_CLI_TLS_CMD -h $fqdn -p $sentinel_service_port sentinel reset ${REDIS_COMPONENT_NAME}
    fi
    if [ $? -eq 0 ]; then
      echo "reset master in sentinel ${sentinel_pod} succeeded"
      exit 0
    fi
  done
  echo "reset master in sentinel failed"
  exit 1
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

reset_master_in_sentinels
