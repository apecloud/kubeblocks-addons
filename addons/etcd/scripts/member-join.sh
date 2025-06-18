#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

add_member() {
  local leader_endpoint join_member_endpoint peer_protocol

  leader_pod_name="${LEADER_POD_FQDN%%.*}"
  leader_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")
  
  # Get join member peer endpoint (handle LB service) - use join member FQDN
  join_member_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$KB_JOIN_MEMBER_POD_NAME" "$KB_JOIN_MEMBER_POD_FQDN")

  peer_protocol=$(get_peer_protocol)
  client_protocol=$(get_client_protocol)

  log "Adding member $KB_JOIN_MEMBER_POD_NAME to cluster via leader $leader_endpoint"
  log "Join member peer URL: $peer_protocol://$join_member_endpoint:2380"

  exec_etcdctl "$client_protocol://$leader_endpoint:2379" member add "$KB_JOIN_MEMBER_POD_NAME" --peer-urls="$peer_protocol://$join_member_endpoint:2380"
}

# Shellspec magic
setup_shellspec

# main
load_common_library
add_member || error_exit "Failed to join member"
