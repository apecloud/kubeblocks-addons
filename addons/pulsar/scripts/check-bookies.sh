#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
 # when running in non-unit test mode, set the options "set -ex".
 set -ex;
}

apply_config_from_env() {
  local cmd="bin/apply-config-from-env.py conf/bookkeeper.conf"
  echo "Applying configuration from environment variables:"
  echo "  - Command: $cmd"
  $cmd
}

wait_for_bookkeeper() {
  local cmd="bin/bookkeeper shell whatisinstanceid"
  echo "Waiting for bookkeeper to start..."
  until $cmd; do
    sleep 3
  done
  echo "Bookkeeper started successfully"
}

merge_bookkeeper_config() {
  local src_config="conf/bookkeeper.conf"
  local dest_config="/opt/pulsar/conf/bookkeeper.conf"

  echo "Merging Pulsar configuration files:"
  echo "  - Source: $src_config"
  echo "  - Destination: $dest_config"
  python3 /kb-scripts/merge_pulsar_config.py "$src_config" "$dest_config"
}

load_env_file() {
  local pulsar_env_config="/opt/pulsar/conf/pulsar.env"

  if [ -f "${pulsar_env_config}" ];then
     source ${pulsar_env_config}
  fi
}

set_tcp_keepalive() {
  local keepalive_time=1
  local keepalive_intvl=11
  local keepalive_probes=3

  echo "Setting TCP keepalive parameters:"
  echo "  - net.ipv4.tcp_keepalive_time=$keepalive_time"
  echo "  - net.ipv4.tcp_keepalive_intvl=$keepalive_intvl"
  echo "  - net.ipv4.tcp_keepalive_probes=$keepalive_probes"

  sysctl -w net.ipv4.tcp_keepalive_time=$keepalive_time
  sysctl -w net.ipv4.tcp_keepalive_intvl=$keepalive_intvl
  sysctl -w net.ipv4.tcp_keepalive_probes=$keepalive_probes
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_env_file
merge_bookkeeper_config
apply_config_from_env
wait_for_bookkeeper
set_tcp_keepalive