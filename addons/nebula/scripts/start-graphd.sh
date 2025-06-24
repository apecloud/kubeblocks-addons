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
exec ${root_dir}/bin/nebula-graphd --flagfile=${root_dir}/etc/nebula-graphd.conf --meta_server_addrs=$NEBULA_METAD_SVC --local_ip=$POD_FQDN --daemonize=false
