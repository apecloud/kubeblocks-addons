#!/bin/bash

endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

echo $endpoints

IFS=',' read -ra ADDR <<< "$endpoints"
for addr in "${ADDR[@]}"; do
  if [[ $addr != http* ]]; then
    addr="http://$addr"
  fi
  servers="${servers},${addr}"
done

servers=${servers:1}

echo $servers

echo "Deleting all keys with prefix /vitess/${KB_CLUSTER_NAME} from Etcd server at ${endpoints}..."
etcdctl --endpoints $servers del /vitess/${KB_CLUSTER_NAME} --prefix

if [ $? -eq 0 ]; then
    echo "Successfully deleted all keys with prefix /vitess/$KB_CLUSTER_NAME."
else
    echo "Failed to delete keys. Please check your Etcd server and try again."
    exit 1
fi
