#!/bin/bash

set -exo pipefail

DOMAIN=$KB_NAMESPACE".svc.cluster.local"
PD_ADDRESS="http://${KB_CLUSTER_NAME}-tidb-pd.${DOMAIN}:2379"
echo "$PD_ADDRESS"
TIKV_ADDRESS="${KB_LEAVE_MEMBER_POD_NAME}.${KB_CLUSTER_NAME}-tikv-headless.${KB_NAMESPACE}.svc:20160"
echo "$TIKV_ADDRESS"
/pd-ctl -u "$PD_ADDRESS" store delete addr "$TIKV_ADDRESS"

until [ $(/pd-ctl -u "$PD_ADDRESS" store | jq "any(.stores[]; select(.store.address == \"$TIKV_ADDRESS\"))") == "false" ]
do
    echo "waiting for tikv node to become tombstone"
    sleep 10
done

echo "removing tombstone"
/pd-ctl -u "$PD_ADDRESS" store remove-tombstone
