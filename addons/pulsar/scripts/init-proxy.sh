#!/bin/bash

wait_for_zookeeper() {
  local zk_servers="$1"
  local zk_domain="${zk_servers%%:*}"
  local zk_port="2181"

  echo "Waiting for Zookeeper at ${zk_servers} to be ready..."
  until zkURL=${zk_servers} python3 /kb-scripts/zookeeper.py get /; do
    sleep 1
  done
  echo "Zookeeper is ready"
}

main() {
  if [ -n "${ZOOKEEPER_SERVERS}" ]; then
    wait_for_zookeeper "${ZOOKEEPER_SERVERS}"
  else
    echo "Zookeeper URL not provided, skipping Zookeeper readiness check"
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
main