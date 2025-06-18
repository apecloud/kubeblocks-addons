#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"



remove_member() {
  local etcd_id="$1"
  local leader_endpoint

  leader_pod_name="${LEADER_POD_FQDN%%.*}"
  leader_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")

  log "Removing member $etcd_id via leader $leader_endpoint"
  exec_etcdctl "$leader_endpoint:2379" member remove "$etcd_id"
}

member_leave() {
  local leaver_endpoint etcd_id

  leaver_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$KB_LEAVE_MEMBER_POD_NAME" "$KB_LEAVE_MEMBER_POD_FQDN")
  [ -z "$leaver_endpoint" ] && error_exit "leave member pod endpoint is empty"

  log "Getting etcd ID for leaving member: $leaver_endpoint"
  etcd_id=$(get_etcd_id "$leaver_endpoint:2379")
  [ -z "$etcd_id" ] && error_exit "Failed to get etcd ID"

  remove_member "$etcd_id" || error_exit "Failed to remove member"
}

# Shellspec magic
setup_shellspec

# main
load_common_library
member_leave
echo "Member leave successfully"
