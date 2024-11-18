#!/bin/bash

# reference: tidb-operator's start script
# https://github.com/pingcap/tidb-operator/blob/master/pkg/manager/member/startscript/v2/pd_start_script.go

set_join_args() {
    # The /join detection is from tidb-operator's script.
    # Normally when a pod restarts, pd reads cluster info from its persistent storage,
    # and does not need --join args. So I suppose this is for the circumstance that
    # a pod fails when during the cluster joining process.
    if [[ -f $DATA_DIR/join ]]; then
        echo "restarted pod, join cluster"
        join=$(cat $DATA_DIR/join | tr "," "\n" | awk -F'=' '{print $2}' | tr "\n" ",")
        join=${join%,}
        ARGS="${ARGS} --join=${join}"
    elif [[ ! -d $DATA_DIR/member/wal ]]; then
        echo "first started pod"
        replicas=$(echo "${PD_POD_FQDN_LIST}" | tr ',' '\n')
        # FIXME: Relying on leader status to determine whether to join or initialize a cluster 
        # is unreliable. Consider a scenario with 3 pods: 2 start normally, while the 3rd pod 
        # pulls image slowly and is still initializing. During this time, the PD cluster 
        # achieves quorum and begins to work, thus KB's role probe succeeds. 
        # When the third pod eventually starts, it mistakenly attempts to join the 
        # cluster, leading to a failure.
        if [[ -n $PD_LEADER_POD_NAME ]]; then
            echo "joining an existing cluster"
            join=""

            for replica in $replicas; do
                join="${join}http://$replica:2380,"
            done

            join=${join%,}
            ARGS="${ARGS} --join=${join}"
        else
            echo "initializing a cluster"
            PEERS=""

            for replica in $replicas; do
                name=$(echo "$replica" | cut -d "." -f 1)
                PEERS="$PEERS$name=http://$replica:2380,"
            done

            PEERS=${PEERS%,}
            ARGS="${ARGS} --initial-cluster=${PEERS}"
        fi
    fi
    # restarted pod (also a initial cluster) doesn't need --join or --initial-cluster args
}

get_current_pod_fqdn() {
    replicas=$(echo "${PD_POD_FQDN_LIST}" | tr ',' '\n')
    echo "$replicas" | grep "$CURRENT_POD_NAME"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

set -exo pipefail

MY_PEER=$(get_current_pod_fqdn)

DATA_DIR="/var/lib/pd"
ARGS="--name=$HOSTNAME \
    --data-dir=$DATA_DIR \
    --peer-urls=http://0.0.0.0:2380 \
    --advertise-peer-urls=http://$MY_PEER:2380 \
    --client-urls=http://0.0.0.0:2379 \
    --advertise-client-urls=http://$MY_PEER:2379 \
    --config=/etc/pd/pd.toml"

set_join_args
# shellcheck disable=SC2086
# exec args does not need to be quoted
exec /pd-server ${ARGS}
