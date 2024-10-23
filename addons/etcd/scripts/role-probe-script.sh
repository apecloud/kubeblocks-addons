#!/bin/bash

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

get_etcd_role() {
  status=$(exec_etcdctl 127.0.0.1:2379 endpoint status --command-timeout=300ms --dial-timeout=100m)
  IsLeader=$(echo "$status" | awk -F ', ' '{print $5}')
  IsLearner=$(echo "$status" | awk -F ', ' '{print $6}')

  if [ "true" = "$IsLeader" ]; then
    echo "leader"
  elif [ "true" = "$IsLearner" ]; then
    echo "learner"
  elif [ "false" = "$IsLeader" ] && [ "false" = "$IsLearner" ]; then
    echo "follower"
  else
    echo "bad role, please check!" >&2
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
etcd_role=$(get_etcd_role)
status=$?
if [ "$status" -ne 0 ]; then
  exit 1
fi
echo -n "$etcd_role"