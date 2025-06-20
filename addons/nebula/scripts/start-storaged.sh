#!/bin/bash
set -ex
trap : TERM INT
root_dir=/usr/local/nebula
logs_dir=${root_dir}/logs

function tail_logs() {
  while true; do
    sleep 1
    if [[ -f ${logs_dir}/nebula-storaged.INFO || -f ${logs_dir}/nebula-storaged.WARNING || -f ${logs_dir}/nebula-storaged.ERROR ]] ; then
      break
    fi
  done
  tail -F ${logs_dir}/nebula-storaged.{INFO,WARNING,ERROR}
}

function register_storaged() {
  echo "Waiting for graphd service $GRAPHD_SVC_NAME to be ready..."
  until /usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password nebula -e "show spaces"; do sleep 2; done
  touch  /tmp/nebula-storaged-hosts
  echo ADD HOSTS \"${POD_FQDN}\":9779 > /tmp/nebula-storaged-hosts
  exec /usr/local/nebula/console/nebula-console --addr $GRAPHD_SVC_NAME --port $GRAPHD_SVC_PORT --user root --password nebula -f /tmp/nebula-storaged-hosts
  rm /tmp/nebula-storaged-hosts
  echo "Start Console succeeded!"
  exit 0
}

tail_logs &
register_storaged > ${logs_dir}/register_storaged.log 2>&1 &
exec ${root_dir}/bin/nebula-storaged --flagfile=${root_dir}/etc/nebula-storaged.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false
