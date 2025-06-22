#!/bin/bash

# shellcheck disable=SC1091
. "/scripts/common.sh"

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
    echo "leader"
  elif [ "$is_learner" = "true" ]; then
    echo "learner"
  else
    echo "follower"
  fi
}

# Shellspec magic
setup_shellspec

# main
load_common_library
etcd_role=$(get_etcd_role)
echo -n "$etcd_role"
