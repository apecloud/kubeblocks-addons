#!/bin/bash

if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
    echo "switchover not triggered for primary, nothing to do, exit 0."
    exit 0
fi

/tools/syncerctl switchover --primary "$KB_SWITCHOVER_CURRENT_NAME" ${KB_SWITCHOVER_CANDIDATE_NAME:+--candidate "$KB_SWITCHOVER_CANDIDATE_NAME"}