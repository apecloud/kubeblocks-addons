#!/bin/bash
set -exo pipefail
source /scripts/common.sh

leader_fqdn="$KB_SWITCHOVER_CURRENT_FQDN"
candidate_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"

[[ $COMPONENT_REPLICAS -lt 2 ]] && {
	echo "Skip: Keeper switchover requires at least 2 replicas."
	exit 0
}

[[ -n "$candidate_fqdn" ]] || {
	echo "ERROR: ClickHouse Keeper switchover requires KB_SWITCHOVER_CANDIDATE_FQDN." >&2
	exit 1
}

function die() {
	echo "ERROR: $*" >&2
	exit 1
}

bin_path="/opt/bitnami/clickhouse/bin"
version=$("$bin_path/clickhouse-keeper" --version 2>/dev/null || "$bin_path/clickhouse" --version 2>/dev/null) || die "failed to determine ClickHouse Keeper version."
major=$(awk 'match($0, /[0-9]+\./) { print substr($0, RSTART, RLENGTH - 1); exit }' <<<"$version")
[[ "${major:-0}" -ge 24 ]] || die "Keeper switchover requires ClickHouse >= 24 (rqld support)."

[[ "$KB_SWITCHOVER_ROLE" == "leader" ]] || {
	echo "Switchover already completed: action is not running on the leader, current role: ${KB_SWITCHOVER_ROLE:-unknown}."
	exit 0
}

current_leader_fqdn=$(find_leader "${CH_KEEPER_POD_FQDN_LIST}") || die "failed to find current Keeper leader."
[[ "$current_leader_fqdn" == "$candidate_fqdn" ]] && {
	echo "Switchover already completed: candidate $candidate_fqdn is leader."
	exit 0
}
[[ "$current_leader_fqdn" == "$leader_fqdn" ]] || die "Expected current leader $leader_fqdn, but got $current_leader_fqdn"

retry_keeper_operation \
	"candidate_mode=\$(get_mode '$candidate_fqdn')" \
	"[[ \"\$candidate_mode\" == \"follower\" ]]" || die "candidate $candidate_fqdn is not a stable follower, current mode: ${candidate_mode:-unknown}"
[[ "$candidate_mode" == "follower" ]] || die "candidate $candidate_fqdn is not a stable follower, current mode: ${candidate_mode:-unknown}"

retry_keeper_operation \
	"leader_zxid=\$(get_zxid '$leader_fqdn'); candidate_zxid=\$(get_zxid '$candidate_fqdn')" \
	"[[ -n \"\$leader_zxid\" && \"\$leader_zxid\" == \"\$candidate_zxid\" ]]" || die "candidate $candidate_fqdn is not caught up with leader $leader_fqdn (leader_zxid=${leader_zxid:-unknown}, candidate_zxid=${candidate_zxid:-unknown})"
[[ -n "$leader_zxid" && "$leader_zxid" == "$candidate_zxid" ]] || die "candidate $candidate_fqdn is not caught up with leader $leader_fqdn (leader_zxid=${leader_zxid:-unknown}, candidate_zxid=${candidate_zxid:-unknown})"

send_4lw "$candidate_fqdn" "rqld" | grep -q "Sent leadership request" || die "failed to request leadership from candidate $candidate_fqdn"

retry_keeper_operation \
	"new_leader_fqdn=\$(find_leader '${CH_KEEPER_POD_FQDN_LIST}')" \
	"[[ \"\$new_leader_fqdn\" == \"$candidate_fqdn\" ]]" || die "Switchover timeout."

echo "Switchover completed successfully"
