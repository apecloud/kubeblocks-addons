#!/bin/bash

# Return 0 for the intended voter, 1 if absent, and 2 for an identity conflict
# or unreadable membership. Newly added members may not have a name yet.
check_join_member() {
  local endpoint="$1" peer_url="$2" members
  if ! members=$(exec_etcdctl "$endpoint" --dial-timeout=3s --command-timeout=5s member list -w simple); then
    join_membership_query_error=" (query failed)"
    log "Failed to query membership via $endpoint"
    return 2
  fi
  join_membership_query_error=""
  join_membership_snapshot="${members:-<(empty)>}"
  printf '%s\n' "$members" | awk -F ', ' -v name="$KB_JOIN_MEMBER_POD_NAME" -v peer="$peer_url" '
    NF != 6 || $1 !~ /^[0-9a-f]+$/ || ($2 != "started" && $2 != "unstarted") { invalid=1; next }
    $4 == peer {
      found++
      if (($3 != "" && $3 != name) || $6 != "false") conflict=1
    }
    $3 == name && $4 != peer { conflict=1 }
    END {
      if (invalid || conflict || found > 1) exit 2
      if (found == 1) exit 0
      exit 1
    }'
}

# Bound diagnostics so the snapshot fits in the action failure tail.
log_join_membership() {
  log "Last observed membership${join_membership_query_error}: $(printf '%s\n' "$join_membership_snapshot" | awk 'NR <= 20 { print substr($0, 1, 512) }')"
}

# Reconcile engine registration, including add committed but reply/state lost.
add_member() {
  local leader_pod_name leader_endpoint join_member_endpoint peer_protocol peer_url status
  local join_membership_snapshot="<not observed>" join_membership_query_error="" add_result
  leader_pod_name="${LEADER_POD_FQDN%%.*}"
  leader_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")
  join_member_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_JOIN_MEMBER_POD_NAME" "$KB_JOIN_MEMBER_POD_FQDN")
  peer_protocol=$(get_protocol "initial-advertise-peer-urls")
  peer_url="$peer_protocol://$join_member_endpoint:2380"

  log "memberJoin runner=${HOSTNAME:-unknown} target=$KB_JOIN_MEMBER_POD_NAME peer=$peer_url leader=$leader_endpoint"
  if check_join_member "$leader_endpoint:2379" "$peer_url"; then
    log "Member $KB_JOIN_MEMBER_POD_NAME already registered; skipping add"
    return 0
  else
    status=$?
    if [ "$status" -ne 1 ]; then
      log_join_membership
      error_exit "Cannot safely join member: membership unavailable or identity conflict"
      return 1
    fi
  fi

  if exec_etcdctl "$leader_endpoint:2379" --dial-timeout=3s --command-timeout=5s member add "$KB_JOIN_MEMBER_POD_NAME" --peer-urls="$peer_url"; then
    add_result="successful add"
  else
    # The server may have committed the add despite an error reaching this runner.
    add_result="add error"
    log "Member add failed; checking whether the target was registered"
  fi

  # Even a successful command must be followed by an authoritative identity check.
  if check_join_member "$leader_endpoint:2379" "$peer_url"; then
    log "Member $KB_JOIN_MEMBER_POD_NAME registration confirmed after $add_result"
    return 0
  fi
  log_join_membership
  error_exit "Failed to join member: registration could not be confirmed"
  return 1
}

# Keep attempt history bounded and expose a failure tail in the action response.
finish_member_join() {
  local status=$?
  trap - EXIT
  log "memberJoin finished status=$status"
  if [ "$status" -ne 0 ]; then
    tail -n 40 "$join_log" >&3 || true
  fi
  echo "memberJoin status=$status log=$join_log" >&3
  exit "$status"
}

main() {
  set -eo pipefail
  # shellcheck disable=SC1091
  . /scripts/common.sh
  load_common_library
  join_log=/tmp/kb-member-join.log
  exec 3>&2
  if [ -f "$join_log" ] && [ "$(wc -c < "$join_log")" -ge 1048576 ]; then
    mv -f "$join_log" "$join_log.1"
  fi
  echo "memberJoin log=$join_log" >&3
  exec >>"$join_log" 2>&1
  trap finish_member_join EXIT
  add_member
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  main "$@"
fi
