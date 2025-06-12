#!/bin/bash

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -uex;
}

load_common_library() {
  # the kb-common.sh and common.sh scripts are defined in the scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

get_etcd_id() {
  local endpoint="$1"
  exec_etcdctl "$endpoint" endpoint status -w fields | grep -o 'id:"[^"]*"' | cut -d'"' -f2
}

remove_member() {
  local etcd_id="$1"
  local leader_endpoint
  
  # Use standard KubeBlocks environment variables
  # KB_PRIMARY_POD_FQDN: The FQDN of the primary Pod within the replication group
  
  # Get leader endpoint (handle LB service) - use primary pod FQDN
  # Extract primary pod name from FQDN for LB endpoint lookup
  primary_pod_name="${KB_PRIMARY_POD_FQDN%%.*}"
  leader_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$primary_pod_name" "$KB_PRIMARY_POD_FQDN")
  
  log "Removing member $etcd_id via leader $leader_endpoint"
  exec_etcdctl "$leader_endpoint:2379" member remove "$etcd_id"
}

member_leave() {
  local leaver_endpoint etcd_id

  # Use standard KubeBlocks environment variables
  # KB_LEAVE_MEMBER_POD_NAME: The pod name of the replica being removed from the group
  # KB_LEAVE_MEMBER_POD_IP: The IP address of the replica being removed from the group
  
  # Get leave member endpoint (handle LB service) - use leave member IP
  leaver_endpoint=$(get_pod_endpoint_with_lb "$PEER_ENDPOINT" "$KB_LEAVE_MEMBER_POD_NAME" "$KB_LEAVE_MEMBER_POD_IP")
  
  if [ -z "$leaver_endpoint" ]; then
    echo "ERROR: leave member pod endpoint is empty" >&2
    return 1
  fi

  log "Getting etcd ID for leaving member: $leaver_endpoint"
  etcd_id=$(get_etcd_id "$leaver_endpoint:2379")
  if [ -z "$etcd_id" ]; then
    echo "ERROR: Failed to get etcd ID" >&2
    return 1
  fi

  if ! remove_member "$etcd_id"; then
    echo "ERROR: Failed to remove member" >&2
    return 1
  fi

  return 0
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
if member_leave; then
  echo "Member leave successfully"
else
  echo "Failed to leave member" >&2
  exit 1
fi
