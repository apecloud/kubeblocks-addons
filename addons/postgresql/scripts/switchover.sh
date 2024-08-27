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

switchoverWithCandidate() {
  local current_pod_fqdn=$1
  local current_primary_pod_fqdn=$2
  local candidate_pod_fqdn=$3
  # shellcheck disable=SC2016
  curl -s http://$(current_pod_fqdn):8008/switchover -XPOST -d '{"leader":"$(current_primary_pod_fqdn)","candidate":"$(candidate_pod_fqdn)"}'
}

switchoverWithoutCandidate() {
  local current_pod_fqdn=$1
  local current_primary_pod_fqdn=$2
  # shellcheck disable=SC2016
  curl -s http://$(current_pod_fqdn):8008/switchover -XPOST -d '{"leader":"$(current_primary_pod_fqdn)"}'
}

switchover() {
  # CURRENT_POD_NAME defined in the switchover action env and POSTGRES_PRIMARY_POD_NAME defined in the cmpd.spec.vars
  if is_empty "$CURRENT_POD_NAME" || is_empty "$POSTGRES_PRIMARY_POD_NAME"; then
    echo "CURRENT_POD_NAME or POSTGRES_PRIMARY_POD_NAME is not set. Exiting..."
    exit 1
  fi

  # shellcheck disable=SC2207
  primary_pod_name_list=($(split "$POSTGRES_PRIMARY_POD_NAME" ","))
  # if primary_pod_name_list length is not 1, it means the primary pod is not unique.
  if [ "${#primary_pod_name_list[@]}" -ne 1 ]; then
    echo "Error: POSTGRES_PRIMARY_POD_NAME should be a unique pod name. Exiting."
    exit 1
  fi

  # POSTGRES_POD_NAME_LIST and POSTGRES_POD_FQDN_LIST defined in the cmpd.spec.vars
  if is_empty "$POSTGRES_POD_NAME_LIST" || is_empty "$POSTGRES_POD_FQDN_LIST" ; then
    echo "POSTGRES_POD_NAME_LIST or POSTGRES_POD_FQDN_LIST is not set. Exiting..."
    exit 1
  fi

  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$POSTGRES_POD_FQDN_LIST" "$CURRENT_POD_NAME")
  if is_empty "$current_pod_fqdn"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from postgres pod fqdn list: $POSTGRES_POD_FQDN_LIST. Exiting."
    exit 1
  fi

  current_primary_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$POSTGRES_POD_FQDN_LIST" "$CURRENT_PRIMARY_POD_NAME")
  if is_empty "$current_primary_pod_fqdn"; then
    echo "Error: Failed to get current primary pod fqdn: $CURRENT_PRIMARY_POD_NAME from postgres pod fqdn list: $POSTGRES_POD_FQDN_LIST. Exiting."
    exit 1
  fi

  # KB_SWITCHOVER_CANDIDATE_FQDN is built-in env in the switchover action injected by the KubeBlocks controller
  if ! is_empty "$KB_SWITCHOVER_CANDIDATE_FQDN"; then
    switchoverWithCandidate "$current_pod_fqdn" "$current_primary_pod_fqdn" "$KB_SWITCHOVER_CANDIDATE_FQDN"
  else
    switchoverWithoutCandidate "$current_pod_fqdn" "$current_primary_pod_fqdn"
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