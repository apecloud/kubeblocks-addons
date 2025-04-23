#!/bin/bash

set -exo pipefail

if [[ $KB_SWITCHOVER_ROLE != "leader" ]]; then
    echo "switchover not triggered for leader, nothing to do, exit 0."
    exit 0
fi

if [[ -n $KB_SWITCHOVER_CANDIDATE_NAME ]]; then
    result=$(/pd-ctl member leader transfer "$KB_SWITCHOVER_CANDIDATE_NAME")
else
    result=$(/pd-ctl member leader resign)
fi

if [[ $result != "Success!" ]]; then
    echo "switchover failed"
    exit 1
fi
