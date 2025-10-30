#!/bin/bash
set -euxo pipefail
source /scripts/common.sh

leaving_member_fqdn="${KB_POD_FQDN}.cluster.local"

function perform_member_leave() {
  local leader_fqdn pod_ordinal config
  if ! leader_fqdn=$(find_leader "$KB_MEMBER_ADDRESSES"); then
    echo "ERROR: Could not find cluster leader."
    return 1
  fi

  if [[ "$leader_fqdn" == "$leaving_member_fqdn" ]]; then
    echo "INFO: Leaving member $leaving_member_fqdn is current leader, performing switchover."
    export KB_LEADER_POD_FQDN=$leader_fqdn
    export READD=false
    /scripts/keeper-switchover.sh
    return 0
  fi

  if ! pod_ordinal=$(extract_ordinal_from_pod_name "$KB_POD_NAME"); then
    echo "ERROR: Failed to extract pod ordinal."
    return 1
  fi
  local server_id=$((pod_ordinal + 1))
  echo "INFO: Pod ordinal: $pod_ordinal, Server ID: $server_id"

  if ! config=$(get_config "$leader_fqdn"); then
    echo "ERROR: Failed to get configuration from leader $leader_fqdn."
    return 1
  fi
  if ! echo "$config" | grep -q "$leaving_member_fqdn"; then
    echo "INFO: Member $leaving_member_fqdn not found in configuration, already removed"
    return 0
  fi

  keeper_run "$leader_fqdn" "reconfig remove \"$server_id\""
}

if ! perform_member_leave; then
  echo "ERROR: Member leave command failed"
  exit 1
fi
