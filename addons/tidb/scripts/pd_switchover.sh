#!/bin/bash

set -exo pipefail

if [[ -z $KB_SWITCHOVER_ROLE ]]; then
    echo "role can't be empty"
    exit 1
fi

if [[ $KB_SWITCHOVER_ROLE != "leader" ]]; then
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
