#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"


switchover_with_candidate() {
  local current_endpoint candidate_endpoint current_leader candidate_id ids member_id leader_id
  local current_pod_name candidate_pod_name

  current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
  candidate_pod_name="${KB_SWITCHOVER_CANDIDATE_FQDN%%.*}"
  
  current_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$current_pod_name" "$KB_SWITCHOVER_CURRENT_FQDN")
  candidate_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$candidate_pod_name" "$KB_SWITCHOVER_CANDIDATE_FQDN")
  
  current_leader=$(get_current_leader "$current_endpoint:2379")
  if [ "$current_leader" = "$candidate_endpoint:2379" ]; then
    log "Current leader is the same as candidate, no need to switch"
    return 0
  fi

  ids=$(get_member_and_leader_id "$candidate_endpoint:2379")
  candidate_id=$(echo "$ids" | awk '{print $1}')
  
  exec_etcdctl "$current_endpoint:2379" move-leader "$candidate_id"

  ids=$(get_member_and_leader_id "$candidate_endpoint:2379")
  member_id=$(echo "$ids" | awk '{print $1}')
  leader_id=$(echo "$ids" | awk '{print $2}')
  
  if [ "$member_id" = "$leader_id" ]; then
    log "Switchover to candidate $KB_SWITCHOVER_CANDIDATE_FQDN completed successfully"
  else
    error_exit "Switchover failed - candidate is not leader after move-leader command"
  fi
}

switchover_without_candidate() {
  local current_endpoint current_leader leader_id peers_id candidate_id ids member_id new_leader_id
  local current_pod_name

  current_pod_name="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
  current_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$current_pod_name" "$KB_SWITCHOVER_CURRENT_FQDN")

  current_leader=$(get_current_leader "$current_endpoint:2379")
  if [ "$current_endpoint:2379" != "$current_leader" ]; then
    log "Leader has already changed, no switchover needed"
    return 0
  fi

  ids=$(get_member_and_leader_id "$current_endpoint:2379")
  leader_id=$(echo "$ids" | awk '{print $1}')
  
  peers_id=$(exec_etcdctl "$current_endpoint:2379" member list | awk -F', ' '{print $1}')
  candidate_id=$(echo "$peers_id" | grep -v "$leader_id" | head -1)
  
  if [ -z "$candidate_id" ]; then
    error_exit "No candidate found for switchover"
  fi

  exec_etcdctl "$current_endpoint:2379" move-leader "$candidate_id"

  ids=$(get_member_and_leader_id "$current_endpoint:2379")
  member_id=$(echo "$ids" | awk '{print $1}')
  new_leader_id=$(echo "$ids" | awk '{print $2}')
  
  if [ "$member_id" != "$new_leader_id" ]; then
    log "Switchover completed successfully - current node is no longer leader"
  else
    error_exit "Switchover failed - current node is still leader after move-leader command"
  fi
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
