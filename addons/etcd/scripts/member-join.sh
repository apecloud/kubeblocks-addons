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
  set -ex;
}

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

add_member() {
  etcd_name="$1"
  # TODO: TLS and LB service
  exec_etcdctl "http://$LEADER_POD_FQDN:2379" member add "$etcd_name"
}

member_join() {
  add_member "$KB_JOIN_MEMBER_POD_NAME"
  status=$?
  if [ $status -ne 0 ]; then
    echo "ERROR: etcdctl add_member failed" >&2
    return 1
  fi
  return 0
}

# main
load_common_library
if member_join; then
  echo "Member join successfully"
else
  echo "Failed to join member" >&2
  exit 1
fi
