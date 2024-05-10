#!/bin/bash

set -exo pipefail

echo "start pd..."
# TODO: clusterDomain 'cluster.local' requires configurable
DOMAIN=$KB_NAMESPACE".svc.cluster.local"
MY_PEER=$KB_POD_FQDN".cluster.local"
PEERS=""
i=0
while [ $i -lt $KB_REPLICA_COUNT ]; do
    if [ $i -ne 0 ]; then
    PEERS="$PEERS,";
    fi;
    host=$(eval echo \$KB_"$i"_HOSTNAME)
    host=$host"."$DOMAIN
    hostname=${KB_CLUSTER_COMP_NAME}-${i}
    PEERS="$PEERS$hostname=http://$host:2380"
    i=$(( i + 1))
done
exec /pd-server --name="${HOSTNAME}" \
    --data-dir=/var/lib/pd \
    --peer-urls=http://0.0.0.0:2380 \
    --advertise-peer-urls=http://"${MY_PEER}":2380 \
    --client-urls=http://0.0.0.0:2379 \
    --advertise-client-urls=http://"${MY_PEER}":2379 \
    --initial-cluster="${PEERS}"
