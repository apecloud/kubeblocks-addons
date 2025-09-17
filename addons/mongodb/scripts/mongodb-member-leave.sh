#!/bin/bash

retry_count=0
while [[ "$(timeout 5s /tools/syncerctl getrole)" == "primary" ]]; do
    echo "current member role is primary, waiting for switchover done."
    sleep 1
    ((retry_count++))
    if [ $retry_count -gt 60 ]; then
        exit 1
    fi
done

/tools/syncerctl leave --instance "$KB_LEAVE_MEMBER_POD_NAME"