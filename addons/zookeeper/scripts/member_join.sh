#!/bin/bash
set -euo pipefail

if [ -z "${KB_JOIN_MEMBER_POD_NAME:-}" ] || [ -z "${KB_JOIN_MEMBER_POD_FQDN:-}" ]; then
    echo "ERROR: KB_JOIN_MEMBER_POD_NAME and KB_JOIN_MEMBER_POD_FQDN are required" >&2
    exit 1
fi

new_member_index="${KB_JOIN_MEMBER_POD_NAME##*-}"
new_member_fqdn="$KB_JOIN_MEMBER_POD_FQDN"
member_type="participant"
if [ "$new_member_index" -ge 3 ]; then
    member_type="observer"
fi
server_peer_entry="server.${new_member_index}=${new_member_fqdn}:2888:3888:${member_type}"
server_entry="server.${new_member_index}=${new_member_fqdn}:2888:3888:${member_type};2181"

echo "Adding ZooKeeper member: $server_entry"

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

member_index_exists() {
    grep -Eq "^[[:space:]]*server\\.${new_member_index}="
}

member_target_exists() {
    awk -v peer_entry="$server_peer_entry" '
      {
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
        split($0, parts, ";")
        if (parts[1] == peer_entry) {
          found = 1
        }
      }
      END { exit found ? 0 : 1 }
    '
}

current_config="$(get_dynamic_config_or_die)"

if member_target_exists <<< "$current_config"; then
    echo "ZooKeeper member server.${new_member_index} already exists"
    exit 0
fi

if member_index_exists <<< "$current_config"; then
    echo "ERROR: ZooKeeper member server.${new_member_index} already exists with a different endpoint or member type" >&2
    exit 1
fi

zkCli.sh << EOF
addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
reconfig -add $server_entry
EOF

updated_config="$(get_dynamic_config_or_die)"
if ! member_target_exists <<< "$updated_config"; then
    echo "ERROR: ZooKeeper member server.${new_member_index} was not observed after reconfig -add" >&2
    exit 1
fi

echo "ZooKeeper member server.${new_member_index} added"
