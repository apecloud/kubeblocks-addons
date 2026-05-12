#!/bin/bash

set -eo pipefail

# shellcheck source=common.sh
. /scripts/common.sh

set_component_tls_variables

# shellcheck disable=SC2086
/pd-ctl -u $pdAddr $extraArg member 1>&2
# shellcheck disable=SC2086
LEADER_NAME=$(/pd-ctl -u $pdAddr $extraArg member | jq -r '.leader.name')
rtnCode=$?
if [[ $rtnCode != 0 ]]; then
    echo -n "unknown"
elif [ "$LEADER_NAME" == "$HOSTNAME" ]; then
    echo -n "leader"
else
    echo -n "follower"
fi