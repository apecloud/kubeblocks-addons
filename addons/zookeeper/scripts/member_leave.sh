#!/bin/bash
set -euo pipefail

if [ -z "${KB_LEAVE_MEMBER_POD_NAME:-}" ]; then
    echo "ERROR: KB_LEAVE_MEMBER_POD_NAME is required" >&2
    exit 1
fi

leave_member_index="${KB_LEAVE_MEMBER_POD_NAME##*-}"

echo "Removing ZooKeeper member: server.${leave_member_index}"

get_dynamic_config_or_die() {
    local output
    if ! output="$(zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
get /zookeeper/config
EOF
)"; then
        echo "ERROR: failed to read ZooKeeper dynamic config" >&2
        return 1
    fi

    if [ -z "$output" ]; then
        echo "ERROR: invalid ZooKeeper dynamic config output: empty response" >&2
        return 1
    fi

    if grep -Eiq "KeeperErrorCode|Exception|NoAuth|AuthFailed|ConnectionLoss|SessionExpired|Connection refused|Unable to connect" <<< "$output"; then
        echo "ERROR: invalid ZooKeeper dynamic config output: $output" >&2
        return 1
    fi

    if ! grep -Eq "^[[:space:]]*server\\.[0-9]+=" <<< "$output"; then
        echo "ERROR: invalid ZooKeeper dynamic config output: missing server.N entries" >&2
        return 1
    fi

    printf '%s\n' "$output"
}

member_exists() {
    grep -Eq "^[[:space:]]*server\\.${leave_member_index}="
}

current_config="$(get_dynamic_config_or_die)"

if ! member_exists <<< "$current_config"; then
    echo "ZooKeeper member server.${leave_member_index} is already absent"
    exit 0
fi

zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
reconfig -remove ${leave_member_index}
EOF

updated_config="$(get_dynamic_config_or_die)"
if member_exists <<< "$updated_config"; then
    echo "ERROR: ZooKeeper member server.${leave_member_index} was still observed after reconfig -remove" >&2
    exit 1
fi

echo "ZooKeeper member server.${leave_member_index} removed"
