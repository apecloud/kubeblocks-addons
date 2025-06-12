#!/bin/bash
set -ex

load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

get_etcd_role() {
  local status member_id leader_id is_learner
  if ! status=$(exec_etcdctl 127.0.0.1:2379 endpoint status -w fields --command-timeout=300ms --dial-timeout=100ms); then
    echo "ERROR: Failed to get endpoint status" >&2
    return 1
  fi

  member_id=$(echo "$status" | grep -o '"MemberID" : [0-9]*' | awk '{print $3}')
  leader_id=$(echo "$status" | grep -o '"Leader" : [0-9]*' | awk '{print $3}')
  is_learner=$(echo "$status" | grep -o '"IsLearner" : [a-z]*' | awk '{print $3}')

  if [ "$member_id" = "$leader_id" ]; then
    if [ "$is_learner" = "true" ]; then
      echo "learner"
    else
      echo "leader"
    fi
  else
    if [ "$is_learner" = "true" ]; then
      echo "learner"
    else
      echo "follower"
    fi
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
etcd_role=$(get_etcd_role)
echo -n "$etcd_role"