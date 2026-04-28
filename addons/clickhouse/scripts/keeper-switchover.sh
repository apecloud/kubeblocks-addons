#!/bin/bash
set -exo pipefail
source /scripts/common.sh

leader_fqdn="$KB_SWITCHOVER_CURRENT_FQDN"
candidate_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"

[[ $COMPONENT_REPLICAS -lt 2 ]] && exit 0
[[ -z "$candidate_fqdn" ]] && { echo "No candidate specified, exit."; exit 0; }
[[ "$KB_SWITCHOVER_ROLE" != "leader" ]] && { echo "switchover not triggered for primary, nothing to do, exit 0."; exit 0; }

# TODO(future): prefer use ClickHouse Keeper `rcfg` after 26.1.1.912+.

function update_priority() {
	local host="$1"
	local line="$2"
	local priority="$3"
	local base_config="${line%;*}"

	retry_keeper_operation \
		"keeper_run '$host' 'reconfig add \"$base_config;$priority\"'" \
		"echo \"\$(get_config '$host')\" | grep -Fqx \"$base_config;$priority\""
}

candidate_mode=$(get_mode "$candidate_fqdn" 2>/dev/null || true)
if [[ "$candidate_mode" != "follower" ]]; then
	echo "ERROR: candidate $candidate_fqdn is not a stable follower, current mode: ${candidate_mode:-unknown}" >&2
	exit 1
fi

leader_zxid=$(get_zxid "$leader_fqdn" 2>/dev/null || true)
candidate_zxid=$(get_zxid "$candidate_fqdn" 2>/dev/null || true)
if [[ -z "$leader_zxid" || -z "$candidate_zxid" || "$leader_zxid" != "$candidate_zxid" ]]; then
	echo "ERROR: candidate $candidate_fqdn is not caught up with leader $leader_fqdn (leader_zxid=${leader_zxid:-unknown}, candidate_zxid=${candidate_zxid:-unknown})" >&2
	exit 1
fi

current_leader_fqdn=$(find_leader "${CH_KEEPER_POD_FQDN_LIST}" 2>/dev/null || true)
if [[ -n "$current_leader_fqdn" ]] && [[ "$current_leader_fqdn" != "$leader_fqdn" ]]; then
	if [[ "$current_leader_fqdn" == "$candidate_fqdn" ]]; then
		echo "Switchover already completed successfully"
		exit 0
	fi
	echo "ERROR: Expected new leader $candidate_fqdn, but got $current_leader_fqdn" >&2
	exit 1
fi

config=$(get_config "$leader_fqdn")
original_config=$(printf "%s\n" "$config" | grep '^server\..*;participant;')

while IFS= read -r line; do
	if [[ "$line" == server.*";participant;"* ]]; then
		line_fqdn=$(echo "$line" | cut -d'=' -f2 | cut -d':' -f1)
		original_priority="${line##*;}"
		target_priority=1
		[[ "$line_fqdn" == "$candidate_fqdn" ]] && target_priority=8
		[[ "$original_priority" != "$target_priority" ]] && update_priority "$leader_fqdn" "$line" "$target_priority"
	fi
done <<<"$original_config"

send_4lw "$candidate_fqdn" "rqld" | grep -q "Sent leadership request to leader." || {
	echo "ERROR: failed to request leadership from candidate $candidate_fqdn" >&2
	exit 1
}

new_leader_fqdn="$leader_fqdn"
retry_keeper_operation \
	"new_leader_fqdn=\$(find_leader '${CH_KEEPER_POD_FQDN_LIST}')" \
	"[[ \"\$new_leader_fqdn\" == \"$candidate_fqdn\" ]]"

if [[ "$new_leader_fqdn" != "$candidate_fqdn" ]]; then
	echo "ERROR: Expected new leader $candidate_fqdn, but got $new_leader_fqdn" >&2
	exit 1
fi

while IFS= read -r line; do
	if [[ "$line" == server.*";participant;"* ]]; then
		original_priority="${line##*;}"
		current_line=$(get_config "$new_leader_fqdn" | grep -F "${line%;*};" || true)
		current_priority="${current_line##*;}"
		[[ -n "$current_line" && "$current_priority" != "$original_priority" ]] && update_priority "$new_leader_fqdn" "$line" "$original_priority"
	fi
done <<<"$original_config"

echo "Switchover completed successfully"
