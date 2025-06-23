#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

remove_member() {
  local etcd_id="$1"

  leader_endpoint=$(find_leader_endpoint "$PEER_FQDNS" "$PEER_ENDPOINT" "")
  [ -z "$leader_endpoint" ] && error_exit "Failed to find leader endpoint"

  log "Removing member $etcd_id via leader $leader_endpoint"
  exec_etcdctl "$leader_endpoint:2379" member remove "$etcd_id"
}

member_leave() {
  leaver_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_POD_NAME" "$KB_POD_FQDN")
  [ -z "$leaver_endpoint" ] && error_exit "Leave member pod endpoint is empty"

  etcd_id=$(get_member_id_hex "$leaver_endpoint:2379")
  [ -z "$etcd_id" ] && error_exit "Failed to get etcd ID"

  remove_member "$etcd_id" || error_exit "Failed to remove member"
  log "Member $KB_POD_NAME left cluster"
}

# main
member_leave
