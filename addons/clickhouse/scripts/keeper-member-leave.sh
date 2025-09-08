#!/bin/bash
set -exo pipefail
source /scripts/common.sh

leaving_member_fqdn="$KB_LEAVE_MEMBER_POD_FQDN"
leaving_member_name="$KB_LEAVE_MEMBER_POD_NAME"

# 1. Find leader from remaining members (exclude the leaving member)
leader_fqdn=$(find_leader "$CH_KEEPER_POD_FQDN_LIST" "$leaving_member_fqdn")
if [[ -z "$leader_fqdn" ]]; then
  echo "ERROR: Could not find cluster leader."
  exit 1
fi

# 2. Extract ordinal from pod name and calculate server ID
pod_ordinal=$(extract_ordinal_from_pod_name "$leaving_member_name")
server_id=$((pod_ordinal + 1))
echo "INFO: Pod ordinal: $pod_ordinal, Server ID: $server_id"

# 3. Check if member exists in configuration
config=$(get_config "$leader_fqdn")
if ! echo "$config" | grep -q "$leaving_member_fqdn"; then
  echo "INFO: Member $leaving_member_fqdn not found in configuration, already removed"
  exit 0
fi

# 4. Remove member and verify removal with retry
retry_keeper_operation \
  "keeper_run '$leader_fqdn' 'reconfig remove \"$server_id\"'" \
  "! echo \"\$(get_config '$leader_fqdn')\" | grep -q '$leaving_member_fqdn'"

echo "INFO: Member leave completed successfully"
