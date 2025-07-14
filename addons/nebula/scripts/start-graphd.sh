#!/bin/bash
set -ex
trap : TERM INT
root_dir=/usr/local/nebula
logs_dir=${root_dir}/logs

function tail_logs() {
  while true; do
    sleep 1
    if [[ -f ${logs_dir}/nebula-graphd.INFO || -f ${logs_dir}/nebula-graphd.WARNING || -f ${logs_dir}/nebula-graphd.ERROR ]] ; then
      break
    fi
  done
  tail -F ${logs_dir}/nebula-graphd.{INFO,WARNING,ERROR}
}

tail_logs &
if [ -f "${root_dir}/logs/.kb_restore" ]; then
  cp ${root_dir}/config/nebula-graphd.conf ${root_dir}/etc/nebula-graphd.conf
  printf "\n--local_ip=${POD_FQDN}" >> ${root_dir}/etc/nebula-graphd.conf
  ${root_dir}/scripts/nebula.service -c ${root_dir}/etc/nebula-graphd.conf start graphd
  meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1 | cut -d':' -f1)
  until curl -L  http://${meta_ep}:19559/status; do sleep 5; done
  /usr/local/nebula/console/agent  --agent="${POD_FQDN}:8888" --meta="${meta_ep}:9559"
  while true; do
    sleep 5
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
else
  exec ${root_dir}/bin/nebula-graphd --flagfile=${root_dir}/config/nebula-graphd.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false
fi

