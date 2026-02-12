#!/bin/bash

set -ex

load_env_file() {
  local pulsar_env_config="/opt/pulsar/conf/pulsar.env"

  if [ -f "${pulsar_env_config}" ];then
     source ${pulsar_env_config}
  fi
}

start_proxy() {
  load_env_file
  python3 /kb-scripts/merge_pulsar_config.py conf/proxy.conf /opt/pulsar/conf/proxy.conf &&
  bin/apply-config-from-env.py conf/proxy.conf
  echo 'OK' > data/status
  exec bin/pulsar proxy
}

# main
start_proxy