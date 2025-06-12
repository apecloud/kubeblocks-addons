#!/bin/bash

# This is magic for shellspec ut framework.
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -uex;
}

load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

add_member() {
  local leader_endpoint join_member_endpoint peer_protocol
  
  # Use standard KubeBlocks environment variables
  # KB_PRIMARY_POD_FQDN: The FQDN of the primary Pod within the replication group
  # KB_NEW_MEMBER_POD_NAME: The pod name of the replica being added to the group
  # KB_NEW_MEMBER_POD_IP: The IP address of the replica being added to the group
  
  # Get leader endpoint (handle LB service) - use primary pod FQDN
  # Extract primary pod name from FQDN for LB endpoint lookup
  primary_pod_name="${KB_PRIMARY_POD_FQDN%%.*}"
  leader_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$primary_pod_name" "$KB_PRIMARY_POD_FQDN")
  
  # Get join member peer endpoint (handle LB service) - use new member IP
  join_member_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$KB_NEW_MEMBER_POD_NAME" "$KB_NEW_MEMBER_POD_IP")
  
  # Get protocol for peer URLs
  peer_protocol=$(get_peer_protocol)
  
  log "Adding member $KB_NEW_MEMBER_POD_NAME to cluster via leader $leader_endpoint"
  log "Join member peer URL: $peer_protocol://$join_member_endpoint:2380"
  
  exec_etcdctl "$leader_endpoint:2379" member add "$KB_NEW_MEMBER_POD_NAME" --peer-urls="$peer_protocol://$join_member_endpoint:2380"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
add_member || error_exit "Failed to join member"
