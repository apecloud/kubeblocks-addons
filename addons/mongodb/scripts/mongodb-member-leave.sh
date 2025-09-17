#!/bin/bash

if [[ "$(timeout 5s /tools/syncerctl getrole)" == "primary" ]]; then
    echo "current member role is primary."
    exit 1
fi

/tools/syncerctl leave --instance "$KB_LEAVE_MEMBER_POD_NAME"