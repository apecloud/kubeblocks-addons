#!/bin/bash
set -euxo pipefail
source /scripts/common.sh

leader_fqdn="$KB_LEADER_POD_FQDN"
candidate_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"

# 1. Get current config
config=$(get_config "$leader_fqdn")

# 2. Find candidate
if [[ -z "$candidate_fqdn" ]]; then
  candidate_fqdn=$(echo "$config" | grep 'participant' | grep -v "$leader_fqdn" | \
  head -n 1 | cut -d'=' -f2 | cut -d':' -f1)
else
  echo "$config" | grep -qE "^server\.[0-9]+=$candidate_fqdn" || {
    echo "ERROR: Specified candidate '$candidate_fqdn' not found in config."
    exit 1
  }
fi

# 3. Change the priority of the candidate to 8, and the others to 1
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

# 4. remove the leader from the config, only remove one time, because only the leader can remove itself
keeper_run "$leader_fqdn" "reconfig remove '$pre_leader_config_id'"

# 5. Re-add after pre leader reboot
retry_keeper_operation \
  "keeper_run '$candidate_fqdn' 'reconfig add \"$pre_leader\"'" \
  "echo \"\$(get_config '$candidate_fqdn')\" | grep -q \"$pre_leader\""

# 6. Check if the candidate is the leader
retry_keeper_operation \
  "mode=\$(get_mode_by_keeper '$candidate_fqdn')" \
  "[[ \"\$mode\" == \"leader\" ]]"
