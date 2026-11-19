#!/bin/bash

set -o pipefail

get_zk_mode_from_script() {
  $ZOOBINDIR/zkServer.sh status
}

get_zookeeper_mode() {
  local stat mode
  if command -v nc >/dev/null 2>&1; then
    if ! stat=$(echo srvr | nc 127.0.0.1 2181 | grep '^Mode:'); then
      return 1
    fi
  else
    if ! stat=$(get_zk_mode_from_script | grep '^Mode:'); then
      return 1
    fi
  fi

  mode=$(echo "$stat" | awk '{print $2}')
  case "$mode" in
    standalone|leader|follower|observer)
      printf "%s" "$mode"
      ;;
    *)
      return 1
      ;;
  esac
}

get_zk_role() {
  local mode
  mode=$(get_zookeeper_mode) || return 1
  case "$mode" in
    standalone)
      printf "leader"
      ;;
    leader|follower|observer)
      printf "%s" "$mode"
      ;;
    *)
      return 1
      ;;
  esac
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
get_zk_role
