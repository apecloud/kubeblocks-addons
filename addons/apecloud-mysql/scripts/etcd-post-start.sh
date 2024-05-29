#!/bin/bash
endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

ehco $endpoints

cell=${CELL:-'zone1'}
export ETCDCTL_API=2

etcdctl --endpoints "http://${endpoints}" get "/vitess/${KB_CLUSTER_NAME}/global" >/dev/null 2>&1
if [[ $? -eq 1 ]]; then
  exit 0
fi

echo "add /vitess/$KB_CLUSTER_NAME/global"
etcdctl --endpoints "http://${endpoints}" mkdir /vitess/${KB_CLUSTER_NAME}/global

echo "add /vitess/$KB_CLUSTER_NAME/$cell"
etcdctl --endpoints "http://${endpoints}" mkdir /vitess/${KB_CLUSTER_NAME}/$cell

# And also add the CellInfo description for the cell.
# If the node already exists, it's fine, means we used existing data.
echo "add $cell CellInfo"
set +e
vtctl --topo_implementation etcd2 \
  --topo_global_server_address "${endpoints}" \
  --topo_global_root /vitess/${KB_CLUSTER_NAME}/global VtctldCommand AddCellInfo \
  --root /vitess/${KB_CLUSTER_NAME}/$cell \
  --server-address "${endpoints}" \
  $cell

