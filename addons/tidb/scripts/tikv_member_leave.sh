#!/bin/bash

set -exo pipefail

# shellcheck source=common.sh
. /scripts/common.sh

set_component_tls_variables

TIKV_ADDRESS="${KB_LEAVE_MEMBER_POD_FQDN}:20160"
echo "$TIKV_ADDRESS"
# shellcheck disable=SC2086
output=$(/pd-ctl -u "$scheme://$PD_ADDRESS" $extraArg store delete addr "$TIKV_ADDRESS")
echo "$output"
# ignore not found nodes to make the script idempotent
if [[ $output != "Success!" && ! $output =~ not\ found ]]; then
    echo "leave member $TIKV_ADDRESS failed"
    exit 1
fi

# shellcheck disable=SC2086
until [[ $(/pd-ctl -u "$scheme://$PD_ADDRESS" $extraArg store | jq "any(.stores[]; select(.store.address == \"$TIKV_ADDRESS\"))") == "false" ]]
do
    echo "waiting for tikv node to become tombstone"
    sleep 10
done

echo "removing tombstone"
# shellcheck disable=SC2086
/pd-ctl -u "$scheme://$PD_ADDRESS" $extraArg store remove-tombstone
