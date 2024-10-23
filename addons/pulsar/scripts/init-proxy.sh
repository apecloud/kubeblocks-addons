#!/bin/bash

wait_for_zookeeper() {
  local zk_url="$1"
  local zk_domain="${zk_url%%:*}"
  local zk_port="2181"

  echo "Waiting for Zookeeper at ${zk_url} to be ready..."
  until echo ruok | nc -q 1 ${zk_domain} ${zk_port} | grep imok; do
    sleep 1
  done
  echo "Zookeeper is ready"
}

main() {
  if [ -n "${metadataStoreUrl}" ]; then
    wait_for_zookeeper "${metadataStoreUrl}"
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