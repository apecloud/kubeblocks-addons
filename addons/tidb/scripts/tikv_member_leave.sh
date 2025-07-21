#!/bin/bash

set -exo pipefail

TIKV_ADDRESS="${KB_LEAVE_MEMBER_POD_NAME}.${TIKV_HEADLESS_SVC_ADDRESS}"
echo "$TIKV_ADDRESS"
output=$(/pd-ctl -u "$PD_ADDRESS" store delete addr "$TIKV_ADDRESS")
if [[ $output != "Success!" && ! $output =~ not\ found ]]; then
    echo "leave member $TIKV_ADDRESS failed"
    exit 1
fi

until [[ $(/pd-ctl -u "$PD_ADDRESS" store | jq "any(.stores[]; select(.store.address == \"$TIKV_ADDRESS\"))") == "false" ]]
do
    echo "waiting for tikv node to become tombstone"
    sleep 10
done

echo "removing tombstone"
/pd-ctl -u "$PD_ADDRESS" store remove-tombstone
