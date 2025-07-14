#!/bin/bash
set -ex
trap : TERM INT
root_dir=/usr/local/nebula
logs_dir=${root_dir}/logs

function tail_logs() {
  while true; do
    sleep 1
    if [[ -f ${logs_dir}/nebula-metad.INFO || -f ${logs_dir}/nebula-metad.WARNING || -f ${logs_dir}/nebula-metad.ERROR ]] ; then
      break
    fi
  done
  tail -F ${logs_dir}/nebula-metad.{INFO,WARNING,ERROR}
}

tail_logs &

if [ -f "${root_dir}/logs/.kb_restore" ]; then
  # TODO: restore data, start agent
  cp ${root_dir}/config/nebula-metad.conf ${root_dir}/etc/nebula-metad.conf
  printf "\n--local_ip=${POD_FQDN}" >> ${root_dir}/etc/nebula-metad.conf
  ${root_dir}/scripts/nebula.service -c ${root_dir}/etc/nebula-metad.conf start metad
  until curl -L  http://${POD_FQDN}:19559/status; do sleep 5; done
  /usr/local/nebula/console/agent  --agent="${POD_FQDN}:8888" --meta="${POD_FQDN}:9559"
  while true; do
    sleep 5
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
else
  exec ${root_dir}/bin/nebula-metad --flagfile=${root_dir}/config/nebula-metad.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false
fi


#