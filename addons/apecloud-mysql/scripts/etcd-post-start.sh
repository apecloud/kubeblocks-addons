#!/bin/bash
endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}
cell=${CELL:-'zone1'}

servers=""
IFS=',' read -ra ADDR <<< "$endpoints"
for addr in "${ADDR[@]}"; do
  if [[ $addr != http* ]]; then
    addr="http://$addr"
  fi
  servers="${servers},${addr}"
done

servers=${servers:1}

if [[ ${ETCDCTL_API} -eq "3" ]]; then
  output=$(etcdctl --endpoints="${servers}" get "/vitess/${KB_CLUSTER_NAME}/global" --prefix --keys-only)
  if [[ -n $output ]]; then
    exit 0
  fi
else
  etcdctl --endpoints=${servers} get "/vitess/${KB_CLUSTER_NAME}/global" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    exit 0
  fi

  echo "add /vitess/$KB_CLUSTER_NAME/global"
  etcdctl --endpoints=${servers} mkdir /vitess/${KB_CLUSTER_NAME}/global

  echo "add /vitess/$KB_CLUSTER_NAME/$cell"
  etcdctl --endpoints=${servers} mkdir /vitess/${KB_CLUSTER_NAME}/$cell
fi

echo "add $cell CellInfo"
set +e
vtctl --topo_implementation etcd2 \
  --topo_global_server_address "${servers}" \
  --topo_global_root "/vitess/${KB_CLUSTER_NAME}/global" VtctldCommand AddCellInfo \
  --root "/vitess/${KB_CLUSTER_NAME}/$cell" \
  --server-address "${servers}" \
  $cell
set -e