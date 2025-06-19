#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

get_etcd_id() {
  local endpoint="$1"
  decimal_id=$(exec_etcdctl "$endpoint" endpoint status -w fields | grep -o '"MemberID" : [0-9]*' | awk '{print $3}')
  hex_id=$(printf "%x" "$decimal_id")
  echo "$hex_id"
}

remove_member() {
  local etcd_id="$1"

  leader_pod_name="${LEADER_POD_FQDN%%.*}"
  leader_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$leader_pod_name" "$LEADER_POD_FQDN")

  log "Removing member $etcd_id via leader $leader_endpoint"
  exec_etcdctl "$leader_endpoint:2379" member remove "$etcd_id"
}

member_leave() {
  leaver_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$KB_LEAVE_MEMBER_POD_NAME" "$KB_LEAVE_MEMBER_POD_FQDN")
  [ -z "$leaver_endpoint" ] && error_exit "Leave member pod endpoint is empty"

  log "Getting etcd ID for leaving member: $leaver_endpoint"
  etcd_id=$(get_etcd_id "$leaver_endpoint:2379")
  [ -z "$etcd_id" ] && error_exit "Failed to get etcd ID"

  remove_member "$etcd_id" || error_exit "Failed to remove member"
  log "Member $KB_LEAVE_MEMBER_POD_NAME left cluster"
}

# Shellspec magic
setup_shellspec

# main
load_common_library
member_leave
