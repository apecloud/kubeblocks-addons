#!/bin/bash

# reference: tidb-operator's start script
# https://github.com/pingcap/tidb-operator/blob/master/pkg/manager/member/startscript/v2/pd_start_script.go

set_scheme() {
    scheme="http"
    if [[ $KB_ENABLE_TLS_BETWEEN_COMPONENTS == "true" ]]; then
        scheme="https"
    fi
}

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
        if [[ -n $PD_LEADER_POD_NAME ]]; then
            echo "query member list from leader"
            leader_fqdn=$(echo "$replicas" | grep "$PD_LEADER_POD_NAME")
            members=$(/pd-ctl --pd "$scheme://$leader_fqdn:2379" member | jq -r '.members[] | .name')
            if echo "$members" | grep -q "$CURRENT_POD_NAME"; then
                echo "current pod already in cluster, delete member first"
                res=$(/pd-ctl --pd "$scheme://$leader_fqdn:2379" member delete name "$CURRENT_POD_NAME")
                if [[ $res != "Success!" ]]; then
                    exit 1
                fi
            fi

            echo "joining an existing cluster"
            join=""

            for replica in $replicas; do
                join="${join}$scheme://$replica:2380,"
            done

            join=${join%,}
            ARGS="${ARGS} --join=${join}"
        else
            echo "initializing a cluster"
            PEERS=""

            for replica in $replicas; do
                name=$(echo "$replica" | cut -d "." -f 1)
                PEERS="$PEERS$name=$scheme://$replica:2380,"
            done

            PEERS=${PEERS%,}
            ARGS="${ARGS} --initial-cluster=${PEERS}"
        fi
    fi
    # restarted pod (also a initial cluster) doesn't need --join or --initial-cluster args
}

get_current_pod_fqdn() {
    if [[ -z $CURRENT_POD_NAME ]]; then
        echo "CURRENT_POD_NAME not set"
        exit 1
    fi
    if [[ -z $PD_POD_FQDN_LIST ]]; then
        echo "PD_POD_FQDN_LIST not set"
        exit 1
    fi
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

# shellcheck disable=SC1091
. /scripts/common.sh

# write_component_tls_env_to_file
set_scheme

cat /etc/pd/pd.toml

MY_PEER=$(get_current_pod_fqdn)

DATA_DIR="/var/lib/pd"
ARGS="--name=$HOSTNAME \
    --data-dir=$DATA_DIR \
    --peer-urls=$scheme://0.0.0.0:2380 \
    --advertise-peer-urls=$scheme://$MY_PEER:2380 \
    --client-urls=$scheme://0.0.0.0:2379 \
    --advertise-client-urls=$scheme://$MY_PEER:2379 \
    --config=/etc/pd/pd.toml"

set_join_args
# shellcheck disable=SC2086
# exec args does not need to be quoted
exec /pd-server ${ARGS}
