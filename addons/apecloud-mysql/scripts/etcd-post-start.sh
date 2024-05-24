#!/bin/bash
etcd_port=${ETCD_PORT:-'2379'}
etcd_server=${ETCD_SERVER:-'127.0.0.1'}

cell=${CELL:-'zone1'}
export ETCDCTL_API=2

etcdctl --endpoints "http://${etcd_server}:${etcd_port}" get "/vitess/global" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "add /vitess/global"
  etcdctl --endpoints "http://${etcd_server}:${etcd_port}" mkdir /vitess/global
fi

etcdctl --endpoints "http://${etcd_server}:${etcd_port}" get "/vitess/$cell" >/dev/null 2>&1
if [[ $? -ne 0 ]]; then
  echo "add /vitess/$cell"
  etcdctl --endpoints "http://${etcd_server}:${etcd_port}" mkdir /vitess/$cell
fi

echo "add $cell CellInfo"
set +e
vtctl --topo_implementation etcd2 \
  --topo_global_server_address "${etcd_server}:${etcd_port}" \
  --topo_global_root /vitess/global VtctldCommand AddCellInfo \
  --root /vitess/$cell \
  --server-address "${etcd_server}:${etcd_port}" \
  $cell
