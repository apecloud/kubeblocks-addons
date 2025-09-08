#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

if [ $COMPONENT_REPLICAS -lt 2 ]; then
    exit 0
fi

switchover_with_candidate() {
  current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
  candidate_pod_name="${KB_SWITCHOVER_CANDIDATE_FQDN%%.*}"

  current_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$current_pod_name" "$KB_SWITCHOVER_CURRENT_FQDN")
  candidate_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$candidate_pod_name" "$KB_SWITCHOVER_CANDIDATE_FQDN")

  if ! is_leader "$current_endpoint:2379" && is_leader "$candidate_endpoint:2379"; then
    log "Leader has already changed, no switchover needed"
    return 0
  fi

  candidate_id=$(get_member_id_hex "$candidate_endpoint:2379")
  exec_etcdctl "$current_endpoint:2379" move-leader "$candidate_id"

  ! is_leader "$candidate_endpoint:2379" && error_exit "Candidate is not leader"
  log "Switchover to candidate $KB_SWITCHOVER_CANDIDATE_FQDN completed successfully"
}

switchover_without_candidate() {
  current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
  current_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$current_pod_name" "$KB_SWITCHOVER_CURRENT_FQDN")

  ! is_leader "$current_endpoint:2379" && error_exit "Leader has already changed, no switchover needed"

  # get first follower
  leader_id=$(get_member_id "$current_endpoint:2379")
  peers_id=$(exec_etcdctl "$current_endpoint:2379" member list -w fields | awk -F': ' '/^"ID"/ {gsub(/[^0-9]/, "", $2); print $2}')
  candidate_id=$(echo "$peers_id" | grep -v "$leader_id" | head -1)
  [ -z "$candidate_id" ] && error_exit "No candidate found for switchover"
  candidate_id_hex=$(printf "%x" "$candidate_id")

  exec_etcdctl "$current_endpoint:2379" move-leader "$candidate_id_hex"
  is_leader "$current_endpoint:2379" && error_exit "Switchover failed - current node is still leader after move-leader command"
  log "Switchover completed successfully - current node is no longer leader"
}

switchover() {
  if [[ "$LEADER_POD_FQDN" != "$KB_SWITCHOVER_CURRENT_FQDN" ]]; then
    log "switchover action not triggered for leader pod. Exiting."
    exit 0
  fi

  if [ -n "$KB_SWITCHOVER_CANDIDATE_FQDN" ]; then
    switchover_with_candidate
  else
    switchover_without_candidate
  fi

  log "Switchover completed successfully"
}

# Shellspec magic
setup_shellspec

# main
load_common_library
switchover
