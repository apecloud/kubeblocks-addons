#!/bin/bash

set -e

get_current_pod_fqdn() {
    if [[ -z $CURRENT_POD_NAME ]]; then
        echo "CURRENT_POD_NAME not set"
        exit 1
    fi
    if [[ -z $POD_FQDN_LIST ]]; then
        echo "POD_FQDN_LIST not set"
        exit 1
    fi
    replicas=$(echo "${POD_FQDN_LIST}" | tr ',' '\n')
    echo "$replicas" | grep "$CURRENT_POD_NAME"
}

INFLUXDB_HOSTNAME=$(get_current_pod_fqdn)
echo "INFLUXDB_HOSTNAME=$INFLUXDB_HOSTNAME"
export INFLUXDB_HOSTNAME

exec "$@"
