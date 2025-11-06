#!/bin/bash
set -ex
trap : TERM INT
source /scripts/common.sh

function retry_add_hosts() {
  sql="ADD HOSTS \"${POD_FQDN}\":9779"
  until /usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password ${NEBULA_ROOT_PASSWORD} -e "${sql}"; do
     echo "Retrying to add hosts, attempt..."
     sleep 2
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
if [ -f "${root_dir}/logs/.kb_restore" ]; then
  # 1. start agent
  start_nebula_agent

  # 2. start storaged for restoration
  nebula_service_start storaged

  # 3. wait for restoration to complete
  while true; do
    sleep 5
    if [[ ! -f "${root_dir}/logs/.kb_restore" ]]; then
      end_restore storaged
      break
    fi
    echo "$(date): Waiting for Nebula restoration to complete..."
  done
fi

exec ${root_dir}/bin/nebula-storaged --flagfile=${root_dir}/config/nebula-storaged.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false