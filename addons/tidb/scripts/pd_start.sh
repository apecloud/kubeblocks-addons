#!/bin/bash

# reference: tidb-operator's start script
# https://github.com/pingcap/tidb-operator/blob/master/pkg/manager/member/startscript/v2/pd_start_script.go

set -exo pipefail

# TODO: clusterDomain 'cluster.local' requires configurable
DOMAIN=$KB_NAMESPACE".svc.cluster.local"
MY_PEER=$KB_POD_FQDN".cluster.local"

DATA_DIR="/var/lib/pd"
ARGS="--name=$HOSTNAME \
    --data-dir=$DATA_DIR \
    --peer-urls=http://0.0.0.0:2380 \
    --advertise-peer-urls=http://$MY_PEER:2380 \
    --client-urls=http://0.0.0.0:2379 \
    --advertise-client-urls=http://$MY_PEER:2379"

if [[ -f $DATA_DIR/join ]]; then
    echo "restarted pod, join cluster"
    join=$(cat $DATA_DIR/join | tr "," "\n" | awk -F'=' '{print $2}' | tr "\n" ",")
    join=${join%,}
    ARGS="${ARGS} --join=${join}"
elif [[ ! -d $DATA_DIR/member/wal ]]; then
    echo "first started pod"
    if [[ -n $KB_LEADER || -n $KB_FOLLOWERS ]]; then
        echo "joining an existing cluster"
        join=""
        i=0
        while [ $i -lt $KB_REPLICA_COUNT ]; do
            host=$(eval echo \$KB_"$i"_HOSTNAME)
            host=$host"."$DOMAIN
            join="${join}http://$host:2380,"
            i=$(( i + 1))
        done
        join=${join%,}
        ARGS="${ARGS} --join=${join}"
    else
        echo "initializing a cluster"
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
        ARGS="${ARGS} --initial-cluster=${PEERS}"
    fi
fi
# restarted pod, initial cluster doesn't need --join or --initial-cluster args
exec /pd-server ${ARGS}
