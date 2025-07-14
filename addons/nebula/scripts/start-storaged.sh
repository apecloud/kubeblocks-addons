#!/bin/bash
set -ex
trap : TERM INT
root_dir=/usr/local/nebula
logs_dir=${root_dir}/logs

function retry_add_hosts() {
  sql="ADD HOSTS \"${POD_FQDN}\":9779"
  for ((i=1; i<=5; i++)); do
     /usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password ${NEBULA_ROOT_PASSWORD} -e "${sql}"
     if [[ $? -eq 0 ]]; then
       break
     fi
     echo "Retrying to add hosts, attempt $i..."
  done
}

function register_storaged() {
  set +x
  echo "Waiting for graphd service $GRAPHD_SVC_NAME to be ready..."
  until /usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password ${NEBULA_ROOT_PASSWORD} -e "show spaces"; do sleep 2; done
  retry_add_hosts
  echo "Start Console succeeded!"
  set -x
}

function register_storaged_and_tail_logs() {
  register_storaged > ${logs_dir}/register_storaged.log 2>&1
  while true; do
    sleep 1
    if [[ -f ${logs_dir}/nebula-storaged.INFO || -f ${logs_dir}/nebula-storaged.WARNING || -f ${logs_dir}/nebula-storaged.ERROR ]] ; then
      break
    fi
  done
  tail -F ${logs_dir}/nebula-storaged.{INFO,WARNING,ERROR}
}

register_storaged_and_tail_logs &
if [ -f "${root_dir}/data/.kb_restore" ]; then
  # TODO: restore data, start agent
  cp ${root_dir}/etc/nebula-metad.conf ${root_dir}/nebula-metad.conf
  echo "local_ip=${POD_FQDN}" >> ${root_dir}/nebula-metad.conf
  ${root_dir}/scripts/nebula.service -c ${root_dir}/nebula-metad.conf start storaged
  meta_ep=$(echo $NEBULA_METAD_SVC | cut -d',' -f1 | cut -d':' -f1)
  until curl -L  http://${meta_ep}:19559/status; do sleep 5; done
  /usr/local/nebula/console/agent  --agent="${POD_FQDN}:8888" --meta="${POD_FQDN}:9559"
  while true; do
    sleep 5
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
else
  exec ${root_dir}/bin/nebula-storaged --flagfile=${root_dir}/etc/nebula-storaged.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false
fi