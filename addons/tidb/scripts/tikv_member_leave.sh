#!/bin/bash

set -exo pipefail

/pd-ctl -u "$PD_ADDRESS" store delete addr "$KB_LEAVE_MEMBER_POD_FQDN:20160"

until [ $(/pd-ctl -u "$PD_ADDRESS" store | jq "any(.stores[]; select(.store.address == \"$KB_LEAVE_MEMBER_POD_FQDN:20160\"))") == "false" ]
do
    echo "waiting for tikv node to become tombstone"
    sleep 10
done

echo "removing tombstone"
/pd-ctl -u "$PD_ADDRESS" store remove-tombstone
