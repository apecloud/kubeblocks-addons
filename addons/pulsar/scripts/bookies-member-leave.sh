#!/bin/bash

format_bookie() {
  local force=$1
  local delete_cookie=$2

  echo "Formatting Bookie..."
  if [[ $force == "true" && $delete_cookie == "true" ]]; then
    bin/bookkeeper shell bookieformat -nonInteractive -force -deleteCookie || true
  else
    bin/bookkeeper shell bookieformat -nonInteractive || true
  fi
  echo "Bookie formatted"
}

# TODO: this logic should be refactored rather than judging by pod name index
should_format_bookie() {
  local current_pod_name=$1
  local current_component_replicas=$2

  local idx=${current_pod_name##*-}
  if [[ $idx -ge $current_component_replicas && $current_component_replicas -ne 0 ]]; then
    return 0
  else
    return 1
  fi
}

bookies_member_leave() {
  # shellcheck disable=SC2153
  local current_pod_name=${CURRENT_POD_NAME}
  local current_component_replicas=${BOOKKEEPER_COMP_REPLICAS}

  if should_format_bookie "$current_pod_name" "$current_component_replicas"; then
    format_bookie "true" "true"
  else
    echo "Skipping Bookie formatting"
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
bookies_member_leave