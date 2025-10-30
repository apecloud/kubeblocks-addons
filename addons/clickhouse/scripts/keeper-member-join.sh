#!/bin/bash
set -euxo pipefail
source /scripts/common.sh

new_member_fqdn="${KB_POD_FQDN}.cluster.local"
keeper_raft_port=${CLICKHOUSE_KEEPER_RAFT_PORT:-9234}

# 1. Find leader from existing members
leader_fqdn=$(find_leader "$KB_MEMBER_ADDRESSES")
if [[ -z "$leader_fqdn" ]]; then
  echo "ERROR: Could not find cluster leader."
  exit 1
fi

# 2. Extract ordinal from pod name and calculate server ID
pod_ordinal=$(extract_ordinal_from_pod_name "$KB_POD_NAME")
server_id=$((pod_ordinal + 1))
echo "INFO: Pod ordinal: $pod_ordinal, Server ID: $server_id"

# 3. Check if member already exists
config=$(get_config "$leader_fqdn")
if echo "$config" | grep -q "$new_member_fqdn"; then
  echo "INFO: Member $new_member_fqdn already exists in configuration"
  exit 0
fi

# 4. Add member and verify join with retry
new_server_config="server.${server_id}=${new_member_fqdn}:${keeper_raft_port};participant;1"

retry_keeper_operation \
  "keeper_run '$leader_fqdn' 'reconfig add \"$new_server_config\"'" \
  "echo \"\$(get_config '$leader_fqdn')\" | grep -q '$new_member_fqdn' && { mode=\$(get_mode '$new_member_fqdn'); [[ \"\$mode\" == \"follower\" ]] || [[ \"\$mode\" == \"observer\" ]]; }"

echo "INFO: Member join completed successfully"
