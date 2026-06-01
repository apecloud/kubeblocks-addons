#!/bin/bash
set -euo pipefail

if [ -z "${KB_JOIN_MEMBER_POD_NAME:-}" ] || [ -z "${KB_JOIN_MEMBER_POD_FQDN:-}" ]; then
    echo "ERROR: KB_JOIN_MEMBER_POD_NAME and KB_JOIN_MEMBER_POD_FQDN are required"
    exit 1
fi

new_member_index="${KB_JOIN_MEMBER_POD_NAME##*-}"
new_member_fqdn="$KB_JOIN_MEMBER_POD_FQDN"
member_type="participant"
if [ "$new_member_index" -ge 3 ]; then
    member_type="observer"
fi
server_entry="server.${new_member_index}=${new_member_fqdn}:2888:3888:${member_type};2181"

echo "Adding ZooKeeper member: $server_entry"

get_dynamic_config() {
    zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
get /zookeeper/config
EOF
}

member_index_exists() {
    grep -Eq "^[[:space:]]*server\\.${new_member_index}="
}

member_target_exists() {
    grep -Fq "server.${new_member_index}=${new_member_fqdn}:"
}

current_config="$(get_dynamic_config)"

if member_target_exists <<< "$current_config"; then
    echo "ZooKeeper member server.${new_member_index} already exists"
    exit 0
fi

if member_index_exists <<< "$current_config"; then
    echo "ERROR: ZooKeeper member server.${new_member_index} already exists with a different endpoint"
    exit 1
fi

zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
reconfig -add $server_entry
EOF

updated_config="$(get_dynamic_config)"
if ! member_target_exists <<< "$updated_config"; then
    echo "ERROR: ZooKeeper member server.${new_member_index} was not observed after reconfig -add"
    exit 1
fi

echo "ZooKeeper member server.${new_member_index} added"
