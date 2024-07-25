#!/bin/bash

if [ -n "$SERVICE_ETCD_ENDPOINT" ]; then
  endpoints=$SERVICE_ETCD_ENDPOINT
else
# local etcd no need to clean
  exit 0 
fi

echo $endpoints

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

echo "Deleting all keys with prefix /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME} from Etcd server at ${endpoints}..."

# Set different deletion methods according to different etcdctl versions.
if [[ ${ETCDCTL_API} == "3" ]]; then
  etcdctl --endpoints $servers del /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME} --prefix
else 
  etcdctl --endpoints $servers rm -r /vitess/${KB_NAMESPACE}/${KB_CLUSTER_NAME}
fi

if [ $? -eq 0 ]; then
  echo "Successfully deleted all keys with prefix /vitess/${KB_NAMESPACE}/$KB_CLUSTER_NAME."
else
  echo "Failed to delete keys. Please check your Etcd server and try again."
  exit 1
fi