#!/bin/bash

pd_role_probe() {
    RESULT=$(timeout 2 /pd-ctl member 2>/dev/null || true)
    if ! echo "$RESULT" | jq -e '.leader.name' >/dev/null 2>&1; then
        for fqdn in $(echo "$PD_POD_FQDN_LIST" | tr ',' ' '); do
            RESULT=$(timeout 2 /pd-ctl -u "http://${fqdn}:2379" member 2>/dev/null || true)
            if echo "$RESULT" | jq -e '.leader.name' >/dev/null 2>&1; then
                break
            fi
            RESULT=""
        done
    fi
    LEADER_NAME=$(echo "$RESULT" | jq -r '.leader.name // empty' 2>/dev/null)
    if [ -z "$LEADER_NAME" ]; then
        return 1
    fi
    IS_MEMBER=$(echo "$RESULT" | jq -r --arg h "$HOSTNAME" '.members[]?.name // empty | select(. == $h)' 2>/dev/null)
    if [ -z "$IS_MEMBER" ]; then
        return 1
    fi
    if [ "$LEADER_NAME" == "$HOSTNAME" ]; then
        echo -n "leader"
    else
        echo -n "follower"
    fi
}

# shellspec source guard
${__SOURCED__:+false} : || return 0

pd_role_probe || exit 1
