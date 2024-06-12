#!/bin/bash

if [ -z "$ETCD_SERVER" ]; then
  exit 0
fi

echo "Stopping Patroni processes..."
pkill -f patroni
sleep 3

export ETCDCTL_API=${ETCD_API:-'2'}

endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

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

echo "Deleting all keys with prefix /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8} from Etcd server at ${endpoints}..."
etcdctl --endpoints $servers del /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8} --prefix

if [ $? -eq 0 ]; then
    echo "Successfully deleted all keys with prefix /service/${KB_CLUSTER_NAME}-${KB_COMP_NAME}-patroni${KB_CLUSTER_UID_POSTFIX_8}."
else
    echo "Failed to delete keys. Please check your Etcd server and try again."
    exit 0
fi
