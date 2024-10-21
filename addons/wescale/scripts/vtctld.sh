#!/bin/bash
echo "starting vtctl"

if [ -n "$LOCAL_ETCD_POD_FQDN" ]; then
  IFS=',' read -ra ETCD_FDQN_ARRAY <<< "$LOCAL_ETCD_POD_FQDN"
  endpoints=""
  for fdqd in "${ETCD_FDQN_ARRAY[@]}"; do
    endpoints+="${fdqd}:${LOCAL_ETCD_PORT},"
  done
  endpoints="${endpoints%,}"
elif [ -n "$SERVICE_ETCD_ENDPOINT" ]; then
  endpoints="$SERVICE_ETCD_ENDPOINT"
else
  echo "Both LOCAL_POD_ETCD_LIST and SERVICE_ETCD_ENDPOINT are empty. Cannot proceed."
  exit 1
fi

echo $endpoints

/scripts/etcd-post-start.sh

echo "starting vtctld"

cell=${CELL:-'zone1'}
grpc_port=${VTCTLD_GRPC_PORT:-'15999'}
vtctld_web_port=${VTCTLD_WEB_PORT:-'15000'}

topology_fags="--topo_implementation etcd2 --topo_global_server_address ${endpoints} --topo_global_root /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/global"

VTDATAROOT=$VTDATAROOT/vtctld
su vitess <<EOF
mkdir -p $VTDATAROOT
if [ -f $VTDATAROOT/vtctld.pid ]; then
    rm $VTDATAROOT/vtctld.pid
fi
exec vtctld \
$topology_fags \
--alsologtostderr \
--cell $cell \
--service_map 'grpc-vtctl,grpc-vtctld' \
--backup_storage_implementation file \
--file_backup_storage_root $VTDATAROOT/backups \
--log_dir $VTDATAROOT \
--port $vtctld_web_port \
--grpc_port $grpc_port \
--pid_file $VTDATAROOT/vtctld.pid
EOF