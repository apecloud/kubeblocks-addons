#!/bin/bash
set -euxo pipefail
source /scripts/common.sh

leaving_member_fqdn="$KB_POD_FQDN"

# 1. Find leader from remaining members
leader_fqdn=$(find_leader "$KB_MEMBER_ADDRESSES")
if [[ -z "$leader_fqdn" ]]; then
  echo "ERROR: Could not find cluster leader."
  exit 1
fi

# 2. Extract ordinal from pod name and calculate server ID
pod_ordinal=$(extract_ordinal_from_pod_name "$KB_POD_NAME")
server_id=$((pod_ordinal + 1))
echo "INFO: Pod ordinal: $pod_ordinal, Server ID: $server_id"

# 3. Check if member exists in configuration
config=$(get_config "$(normalize_fqdn "$leader_fqdn")")
if ! echo "$config" | grep -q "$leaving_member_fqdn"; then
  echo "INFO: Member $leaving_member_fqdn not found in configuration, already removed"
  exit 0
fi

# 4. Remove member and verify removal with retry
retry_keeper_operation \
  "keeper_run '$leader_fqdn' 'reconfig remove \"$server_id\"'" \
  "! echo \"\$(get_config '$leader_fqdn')\" | grep -q '$leaving_member_fqdn'"

echo "INFO: Member leave completed successfully"
