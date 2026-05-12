#!/bin/bash

set -exo pipefail

if [[ $KB_SWITCHOVER_ROLE != "leader" ]]; then
    echo "switchover not triggered for leader, nothing to do, exit 0."
    exit 0
fi

# shellcheck source=common.sh
. /scripts/common.sh

set_component_tls_variables

if [[ -n $KB_SWITCHOVER_CANDIDATE_NAME ]]; then
    # shellcheck disable=SC2086
    result=$(/pd-ctl -u $pdAddr $extraArg member leader transfer "$KB_SWITCHOVER_CANDIDATE_NAME")
else
    # shellcheck disable=SC2086
    result=$(/pd-ctl -u $pdAddr $extraArg member leader resign)
fi

if [[ $result != "Success!" ]]; then
    echo "switchover failed"
    exit 1
fi
