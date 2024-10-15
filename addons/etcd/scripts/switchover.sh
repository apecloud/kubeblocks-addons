#!/bin/sh

load_common_library() {
  # the kb-common.sh and common.sh scripts are defined in the scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck source=/scripts/kb-common.sh
  . "${kblib_common_library_file}"
  # shellcheck source=/scripts/common.sh
  . "${etcd_common_library_file}"
}

switchover_with_candidate() {
  leader_endpoint=${LEADER_POD_FQDN}:2379
  candidate_endpoint=${KB_SWITCHOVER_CANDIDATE_FQDN}:2379

  current_leader_endpoint=$(get_current_leader_with_retry 3 2)
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "failed to get current leader endpoint" >&2
    return 1
  fi
  
  if [ "$current_leader_endpoint" = "$candidate_endpoint" ]; then
    echo "current leader is the same as candidate, no need to switch"
    return 0
  fi
  
  candidate_id=$(exec_etcdctl_no_check_tls "${candidate_endpoint}" endpoint status | awk -F', ' '{print $2}')
  exec_etcdctl_no_check_tls "${leader_endpoint}" move-leader "$candidate_id"
  
  status=$(exec_etcdctl_no_check_tls "${candidate_endpoint}" endpoint status)
  isLeader=$(echo "${status}" | awk -F ', ' '{print $5}')
  
  if [ "$isLeader" = "true" ]; then
    echo "switchover successfully"
  else
    echo "switchover failed, please check!" >&2
    return 1
  fi
}

switchover_without_candidate() {
  leader_endpoint=${LEADER_POD_FQDN}:2379
  old_leader_endpoint=$leader_endpoint
  
  current_leader_endpoint=$(get_current_leader_with_retry 3 2)
  status=$?
  if [ "$status" -ne 0 ]; then
    echo "failed to get current leader endpoint" >&2
    return 1
  fi
  
  if [ "$old_leader_endpoint" != "$current_leader_endpoint" ]; then
    echo "leader has been changed, do not perform switchover, please check!"
    return 0
  fi
  
  leaderID=$(exec_etcdctl_no_check_tls "${leader_endpoint}" endpoint status | awk -F', ' '{print $2}')
  peerIDs=$(exec_etcdctl_no_check_tls "${leader_endpoint}" member list | awk -F', ' '{print $1}')
  randomcandidate_id=$(echo "$peerIDs" | grep -v "$leaderID" | awk 'NR==1')
  
  if [ -z "$randomcandidate_id" ]; then
    echo "no candidate found" >&2
    return 1
  fi
  
  exec_etcdctl_no_check_tls "$leader_endpoint" move-leader "$randomcandidate_id"
  
  status=$(exec_etcdctl_no_check_tls "$leader_endpoint" endpoint status)
  isLeader=$(echo "$status" | awk -F ', ' '{print $5}')
  
  if [ "$isLeader" = "false" ]; then
    echo "switchover successfully"
  else
    echo "switchover failed, please check!" >&2
    return 1
  fi
}

switchover() {
  if [ -z "$KB_SWITCHOVER_CANDIDATE_FQDN" ]; then
      switchover_without_candidate
  else
      switchover_with_candidate
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
switchover
