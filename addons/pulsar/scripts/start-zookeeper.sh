#!/bin/bash

set -ex


merge_zookeeper_config() {
  local dst_config="conf/zookeeper.conf"
  local src_config="/opt/pulsar/conf/zookeeper.conf"

  echo "Merging Pulsar configuration files:"
  echo "  - Source: $src_config"
  echo "  - Destination: $dst_config"
  python3 /kb-scripts/merge_pulsar_config.py "$dst_config" "$src_config"
}

load_env_file() {
  local pulsar_env_config="/opt/pulsar/conf/pulsar.env"

  if [ -f "${pulsar_env_config}" ];then
     source ${pulsar_env_config}
  fi
}

start_zookeeper() {
  export ZOOKEEPER_SERVERS=${ZK_POD_NAME_LIST}

  load_env_file
  merge_zookeeper_config
  bin/apply-config-from-env.py conf/zookeeper.conf;
  bin/generate-zookeeper-config.sh conf/zookeeper.conf;
  exec bin/pulsar zookeeper;
}

# main
start_zookeeper
