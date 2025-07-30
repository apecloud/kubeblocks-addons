#!/bin/bash
set -ex
trap : TERM INT
root_dir=/usr/local/nebula
logs_dir=${root_dir}/logs

source /scripts/common.sh

tail_logs metad &

if [ -f "${root_dir}/logs/.kb_restore" ]; then
  # 1. start metad
  nebula_service_start metad

  # 2. start agent
  until curl -L  http://${POD_FQDN}:19559/status; do sleep 5; done
  touch ${root_dir}/logs/.kb_agent
  /usr/local/nebula/console/agent  --agent="${POD_FQDN}:8888" --meta="${POD_FQDN}:9559" &

  # 3. wait for restoration to complete
  while true; do
    sleep 5
    if [[ ! -f "${root_dir}/logs/.kb_restore" ]]; then
      end_restore metad
      break
    fi
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
fi

exec ${root_dir}/bin/nebula-metad --flagfile=${root_dir}/config/nebula-metad.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false
