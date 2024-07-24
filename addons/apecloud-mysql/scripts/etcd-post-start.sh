#!/bin/bash
if [ -n "$LOCAL_ETCD_POD_LIST" ]; then
  IFS=',' read -ra ETCD_POD_ARRAY <<< "$LOCAL_ETCD_POD_LIST"
  endpoints=""
  for pod in "${ETCD_POD_ARRAY[@]}"; do
    endpoints+="${pod}.${LOCAL_ETCD_HEADLESS}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:${LOCAL_ETCD_PORT},"
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

if [[ ${ETCDCTL_API} == "3" ]]; then
  output=$(etcdctl --endpoints="${servers}" get "/vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell" --prefix --keys-only)
  if [[ -n $output ]]; then
    exit 0
  fi
else
  etcdctl --endpoints=${servers} get "/vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell" >/dev/null 2>&1
  if [[ $? -eq 0 ]]; then
    exit 0
  fi

  echo "add /vitess/$KB_NAMESPACE/$KB_CLUSTER_NAME/global"
  etcdctl --endpoints=${servers} mkdir /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/global

  echo "add /vitess/$KB_NAMESPACE/$KB_CLUSTER_NAME/$cell"
  etcdctl --endpoints=${servers} mkdir /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}/$cell
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