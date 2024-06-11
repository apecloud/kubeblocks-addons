#!/bin/bash

if [ "$etcdHA" != "true" ]; then
  exit 0
fi
export ETCDCTL_API=${ETCD_API:-'2'}

endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

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

PATRONI_API_URL="http://$KB_POD_NAME:8008/patroni"

PATRONI_SCOPE=$(curl -s $PATRONI_API_URL | jq -r '.patroni.scope')

if [ -z "$PATRONI_SCOPE" ]; then
  echo "Failed to get Patroni scope."
  exit 1
fi

echo "Deleting all keys with prefix /service/$PATRONI_SCOPE from Etcd server at ${endpoints}..."
etcdctl --endpoints $servers del /service/$PATRONI_SCOPE --prefix

if [ $? -eq 0 ]; then
    echo "Successfully deleted all keys with prefix /vitess/${KB_NAMESPACE}/$KB_CLUSTER_NAME."
else
    echo "Failed to delete keys. Please check your Etcd server and try again."
    exit 1
fi
