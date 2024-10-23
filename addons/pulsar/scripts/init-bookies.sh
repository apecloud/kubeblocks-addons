#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
 # when running in non-unit test mode, set the options "set -ex".
 set -ex;
}

wait_for_zookeeper() {
  local zk_servers="$1"
  local zk_domain="${zk_servers%%:*}"
  local zk_port="2181"

  echo "Waiting for Zookeeper at ${zk_servers} to be ready..."
  until echo ruok | nc -q 1 ${zk_domain} ${zk_port} | grep imok; do
    sleep 1
  done
  echo "Zookeeper is ready"
}

merge_bookkeeper_config() {
  local src_config="conf/bookkeeper.conf"
  local dest_config="/opt/pulsar/conf/bookkeeper.conf"

  echo "Merging Pulsar configuration files:"
  echo "  - Source: $src_config"
  echo "  - Destination: $dest_config"
  python3 /kb-scripts/merge_pulsar_config.py "$src_config" "$dest_config"
}

apply_config_from_env() {
  local config_file="conf/bookkeeper.conf"

  echo "Applying configuration from environment variables to $config_file"
  bin/apply-config-from-env.py "$config_file"
}

init_bookkeeper_cluster() {
  echo "Checking if BookKeeper cluster is already initialized..."
  if bin/bookkeeper shell whatisinstanceid; then
    echo "BookKeeper cluster is already initialized"
  else
    echo "Initializing new BookKeeper cluster"
    bin/bookkeeper shell initnewcluster
  fi
}

init_bookies() {
  if [[ -z "$zkServers" ]]; then
    echo "Error: zkServers environment variable is not set, Please set the zkServers environment variable and try again."
    exit 1
  fi

  wait_for_zookeeper "$zkServers"
  merge_bookkeeper_config
  apply_config_from_env
  init_bookkeeper_cluster
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
init_bookies