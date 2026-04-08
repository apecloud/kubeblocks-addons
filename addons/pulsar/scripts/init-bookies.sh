#!/bin/bash

wait_for_zookeeper() {
  local zk_servers="$1"
  echo "Waiting for Zookeeper at ${zk_servers} to be ready..."
  until zkURL=${zk_servers} python3 /kb-scripts/zookeeper.py get /; do
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

decommission_old_bookie() {
  if [[ ! -d "/pulsar/data/bookkeeper/journal/" || ! -d "/pulsar/data/bookkeeper/ledgers/" ]]; then
    echo "Journal or ledgers directory does not exist, skip decommission old bookie"
    return
  fi
  
  # when an bookie is rebuilt, it will keep crashing due to the old cookie in zookeeper
  echo "checking if data dir is empty..."
  if [[ -f "/pulsar/data/bookkeeper/journal/current/VERSION" || -f "/pulsar/data/bookkeeper/ledgers/current/VERSION" ]]; then
    echo "Data dir is not empty, skip decommission old bookie"
  else
    echo "Data dir is empty"
    fqdn=$(echo "$BOOKKEEPER_POD_FQDN_LIST" | tr ',' '\n' | grep "$CURRENT_POD_NAME")
    echo "Decommissioning old bookie with id $fqdn"
    if ! bin/bookkeeper shell decommissionbookie -bookieid "$fqdn:3181" | tee /tmp/decommission.log; then
      # shellcheck disable=SC2016
      if cat /tmp/decommission.log | grep -q 'org.apache.zookeeper.KeeperException$NoNodeException'; then
        echo "Bookie $fqdn is not registered in zookeeper, skip decommission"
      else
        echo "Failed to decommission bookie $fqdn"
        exit 1
      fi
    else
      echo "Bookie $fqdn decommissioned successfully"
    fi
  fi
}

load_env_file() {
  local pulsar_env_config="/opt/pulsar/conf/pulsar.env"

  if [ -f "${pulsar_env_config}" ];then
     source ${pulsar_env_config}
  fi
}

init_bookies() {
  if [[ -z "$ZOOKEEPER_SERVERS" ]]; then
    echo "Error: ZOOKEEPER_SERVERS environment variable is not set, Please set the ZOOKEEPER_SERVERS environment variable and try again."
    exit 1
  fi

  wait_for_zookeeper "$ZOOKEEPER_SERVERS"
  merge_bookkeeper_config
  apply_config_from_env
  load_env_file
  init_bookkeeper_cluster
  decommission_old_bookie
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

set -exo pipefail;

# main
init_bookies