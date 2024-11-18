#!/bin/bash


get_zookeeper_mode() {
  if command -v nc >/dev/null 2>&1; then
    local stat
    stat=$(echo srvr | nc 127.0.0.1 2181 | grep Mode)
    echo "$stat" | awk '{print $2}'
  else
    local stat
    stat=$($ZOOBINDIR/zkServer.sh status)
    echo "$stat" | grep "Mode:" | awk '{print $2}'
  fi
}

get_zk_role() {
  local mode
  mode=$(get_zookeeper_mode)
  if [[ "$mode" == "standalone" ]]; then
    printf "leader"
  else
    printf "%s" "$mode"
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
get_zk_role