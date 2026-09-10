#!/bin/bash

current_role=$(timeout 5s /tools/syncerctl getrole)
role_rc=$?
if [ "$role_rc" -ne 0 ]; then
    echo "failed to determine current member role (rc=$role_rc)." >&2
    exit "$role_rc"
fi

if [[ "$current_role" == "primary" ]]; then
    echo "current member role is primary."
    exit 1
fi

/tools/syncerctl leave --instance "$KB_LEAVE_MEMBER_POD_NAME"
