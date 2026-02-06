#!/bin/bash
set -ex
trap : TERM INT

source /scripts/common.sh

tail_logs graphd &

if [ -f "${root_dir}/logs/.kb_restore" ]; then
  # 1. start agent
  start_nebula_agent

  # 2. start graphd for restoration
  nebula_service_start graphd

  # 3. wait for restoration to complete
  while true; do
    sleep 5
    if [[ ! -f "${root_dir}/logs/.kb_restore" ]]; then
      end_restore graphd
      break
    fi
    check_agent
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
fi

exec ${root_dir}/bin/nebula-graphd --flagfile=${root_dir}/config/nebula-graphd.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false