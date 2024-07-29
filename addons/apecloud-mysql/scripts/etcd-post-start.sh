#!/bin/bash
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

echo $servers

if [[ ${ETCDCTL_API} == "2" ]]; then
  # etcdctl API 2 manages data in a directory-based format, requiring directories to be created in advance.
  etcdctl --endpoints=${servers} get "/vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    exit 0
  fi
  echo "add /vitess/$KB_NAMESPACE/$KB_CLUSTER_NAME/global"
  etcdctl --endpoints=${servers} mkdir /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/global
  echo "add /vitess/$KB_NAMESPACE/$KB_CLUSTER_NAME/$cell"
  etcdctl --endpoints=${servers} mkdir /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell
else
  # etcdctl API 3 manages data in key-value pairs, eliminating the need to create additional directories.
  output=$(etcdctl --endpoints="${servers}" get "/vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell" --prefix --keys-only)
  if [[ -n $output ]]; then
    exit 0
  fi
fi

echo "add $cell CellInfo"
set +e
vtctl --topo_implementation etcd2 \
  --topo_global_server_address "${servers}" \
  --topo_global_root "/vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/global" VtctldCommand AddCellInfo \
  --root "/vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell" \
  --server-address "${servers}" \
  $cell
set -e