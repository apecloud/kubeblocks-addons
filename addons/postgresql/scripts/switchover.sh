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
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/kb-scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

switchover_with_candidate() {
  local current_pod_fqdn=$1
  local current_primary_pod_name=$2
  # shellcheck disable=SC2034
  local candidate_pod_name=$3
  # TODO: check the role in kernel before switchover
  echo "Current pod: ${current_pod_fqdn} perform switchover with candidate. Leader: ${current_primary_pod_name}, Candidate: ${candidate_pod_name}"
  switchover_output=$(curl -s "http://127.0.0.1:8008/switchover" -XPOST -d "{\"leader\":\"${current_primary_pod_name}\",\"candidate\":\"${candidate_pod_name}\"}")
  echo "Switchover with candidate output: ${switchover_output}"
  # TODO: check switchover result
}

switchover_without_candidate() {
  local current_pod_fqdn=$1
  # shellcheck disable=SC2034
  local current_primary_pod_name=$2
  # TODO: check the role in kernel before switchover
  echo "Current pod: ${current_pod_fqdn} perform switchover without candidate. Leader: ${current_primary_pod_name}"
  switchover_output=$(curl -s "http://127.0.0.1:8008/switchover" -XPOST -d "{\"leader\":\"${current_primary_pod_name}\"}")
  echo "Switchover without candidate output: ${switchover_output}"
  # TODO: check switchover result
}

switchover() {

  POSTGRES_PRIMARY_POD_NAME=$(curl -s http://localhost:8008/cluster | jq -r '.members[] | select (.role == "leader") | .name')

  # CURRENT_POD_NAME defined in the switchover action env
  if is_empty "$CURRENT_POD_NAME" ; then
    echo "CURRENT_POD_NAME is not set. Exiting..."
    exit 1
  fi

  if [[ $POSTGRES_PRIMARY_POD_NAME != "$CURRENT_POD_NAME" ]]; then
    echo "switchover action not triggered for non-primary pod. Exiting."
    exit 0
  fi

  # KB_SWITCHOVER_CANDIDATE_NAME is built-in env in the switchover action injected by the KubeBlocks controller
  if ! is_empty "$KB_SWITCHOVER_CANDIDATE_NAME"; then
    switchover_with_candidate "$CURRENT_POD_NAME" "$POSTGRES_PRIMARY_POD_NAME" "$KB_SWITCHOVER_CANDIDATE_NAME"
  else
    switchover_without_candidate "$CURRENT_POD_NAME" "$POSTGRES_PRIMARY_POD_NAME"
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

if [ "$KB_SWITCHOVER_ROLE" != "primary" ]; then
  echo "switchover not triggered for primary, nothing to do, exit 0."
  exit 0
fi
# main
load_common_library
switchover