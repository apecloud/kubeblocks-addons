#!/bin/bash
set -euo pipefail

if [ -z "${KB_LEAVE_MEMBER_POD_NAME:-}" ]; then
    echo "ERROR: KB_LEAVE_MEMBER_POD_NAME is required"
    exit 1
fi

leave_member_index="${KB_LEAVE_MEMBER_POD_NAME##*-}"

echo "Removing ZooKeeper member: server.${leave_member_index}"

get_dynamic_config() {
    zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
get /zookeeper/config
EOF
}

member_exists() {
    grep -Eq "^[[:space:]]*server\\.${leave_member_index}="
}

current_config="$(get_dynamic_config)"

if ! member_exists <<< "$current_config"; then
    echo "ZooKeeper member server.${leave_member_index} is already absent"
    exit 0
fi

zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
reconfig -remove ${leave_member_index}
EOF

updated_config="$(get_dynamic_config)"
if member_exists <<< "$updated_config"; then
    echo "ERROR: ZooKeeper member server.${leave_member_index} was still observed after reconfig -remove"
    exit 1
fi

echo "ZooKeeper member server.${leave_member_index} removed"
