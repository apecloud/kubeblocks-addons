#!/bin/bash

if [ -z "$ETCD_SERVER" ]; then
  exit 0
fi

IFS=',' read -ra ADDR <<< "$KB_CLUSTER_COMPONENT_POD_IP_LIST"
FIRST_IP=${ADDR[0]}

PATRONI_API_URL="http://$FIRST_IP:8008/patroni"
PATRONI_SHUTDOWN_URL="http://$FIRST_IP:8008/shutdown"

status_code=$(curl -s -o /dev/null -w "%{http_code}" $PATRONI_API_URL)

if [ "$status_code" -ne 200 ]; then
  echo "Failed to access Patroni API at $PATRONI_API_URL. HTTP response code: $status_code."
  exit 0
fi

response=$(curl -s -o /dev/null -w "%{http_code}" -XPOST $PATRONI_SHUTDOWN_URL)

if [ "$response" -eq 200 ]; then
  echo "Successfully terminated Patroni service at $FIRST_IP."
else
  echo "Failed to terminate Patroni service at $FIRST_IP. HTTP response code: $response."
  sleep 10
  exit 0
fi
sleep 10

export ETCDCTL_API=${PATRONI_DCS_ETCD_VERSION:-'2'}

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
