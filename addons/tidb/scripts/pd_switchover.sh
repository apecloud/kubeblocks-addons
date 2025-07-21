#!/bin/bash
set -euxo pipefail

pd_url="http://${KB_LEADER_POD_FQDN}:2379"
if [ -z "$KB_SWITCHOVER_CANDIDATE_NAME" ]; then
    result=$(/pd-ctl --pd "$pd_url" member leader resign)
else
    result=$(/pd-ctl --pd "$pd_url" member leader transfer "$KB_SWITCHOVER_CANDIDATE_NAME")
fi

if [[ $result != "Success!" ]]; then
    echo "switchover failed"
    exit 1
fi
