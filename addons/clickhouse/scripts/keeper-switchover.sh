#!/bin/bash
set -exo pipefail
source /scripts/common.sh

leader_fqdn="$KB_SWITCHOVER_CURRENT_FQDN"
candidate_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"

if [ $COMPONENT_REPLICAS -lt 2 ]; then
    exit 0
fi

if [ -z $candidate_fqdn ]; then
    echo "No candidate specified, exit."
    exit 0
fi

if [ "$KB_SWITCHOVER_ROLE" != "leader" ]; then
    echo "switchover not triggered for primary, nothing to do, exit 0."
    exit 0
fi


# 1. Get current config
config=$(get_config "$leader_fqdn")

# 2. Change the priority of the candidate to 8, and the others to 1
pre_leader=$(echo "$config" | grep "$leader_fqdn")
pre_leader=${pre_leader%;*}";1"
pre_leader_config_name=$(echo "$pre_leader" | cut -d'=' -f1)
pre_leader_config_id=$(echo "$pre_leader_config_name" | cut -d'.' -f2)
# server.1=ch-cluster-ch-keeper-0.ch-cluster-ch-keeper-headless.default.svc.cluster.local:9234;participant;1
while IFS= read -r line; do
  if [[ "$line" == server.*";participant;"* ]]; then
    line_fqdn=$(echo "$line" | cut -d'=' -f2 | cut -d':' -f1)
    original_priority="${line##*;}"
    base_config="${line%;*}"
    new_priority=""
    if echo "$line_fqdn" | grep -q "$candidate_fqdn"; then
      [[ "$original_priority" -ne 8 ]] && new_priority=8
    else
      [[ "$original_priority" -ne 1 ]] && new_priority=1
    fi
    [[ -n "$new_priority" ]] && retry_keeper_operation \
      "keeper_run '$leader_fqdn' 'reconfig add \"$base_config;$new_priority\"'" \
      "echo \"\$(get_config '$leader_fqdn')\" | grep -q \"$base_config;$new_priority\""
  fi
done <<< "$config"

# 3. Remove the leader from the config, remove once, because only the leader can remove itself
keeper_run "$leader_fqdn" "reconfig remove '$pre_leader_config_id'"

# 4. Re-add after pre leader reboot
retry_keeper_operation \
  "keeper_run '$candidate_fqdn' 'reconfig add \"$pre_leader\"'" \
  "get_config '$candidate_fqdn' | grep -q '$pre_leader'"

# 5. Check if the candidate is the leader
retry_keeper_operation \
  "mode=\$(get_mode_by_keeper '$candidate_fqdn')" \
  "[[ \"\$mode\" == \"leader\" ]]"

echo "Switchover completed successfully"
