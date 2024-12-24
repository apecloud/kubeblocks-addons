#!/bin/bash

set -ex

load_env_file() {
  local pulsar_env_config="/opt/pulsar/conf/pulsar.env"

  if [ -f "${pulsar_env_config}" ];then
     source ${pulsar_env_config}
  fi
}

merge_bookkeeper_config() {
  local src_config="conf/bookkeeper.conf"
  local dest_config="/opt/pulsar/conf/bookkeeper.conf"

  echo "Merging Pulsar configuration files:"
  echo "  - Source: $src_config"
  echo "  - Destination: $dest_config"
  python3 /kb-scripts/merge_pulsar_config.py "$src_config" "$dest_config"
}

start_bookkeeper() {
  load_env_file
  merge_bookkeeper_config
  bin/apply-config-from-env.py conf/bookkeeper.conf
  exec bin/bookkeeper autorecovery
}

# main
start_bookkeeper