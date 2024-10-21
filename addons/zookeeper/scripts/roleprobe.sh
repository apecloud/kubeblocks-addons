#!/bin/bash

zk_env_file="$ZOOBINDIR"/zkEnv.sh

load_zk_env() {
  # shellcheck source=$ZOOBINDIR"/zkEnv.sh
  source "$zk_env_file" > /dev/null
}

get_zookeeper_mode() {
  local stat
  stat=$(java -cp "$CLASSPATH" $CLIENT_JVMFLAGS $JVMFLAGS org.apache.zookeeper.client.FourLetterWordMain localhost 2181 srvr 2> /dev/null | grep Mode)
  echo "$stat" | awk -F': ' '{print $2}' | tr -d '[:space:]\n'
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
load_zk_env
get_zk_role