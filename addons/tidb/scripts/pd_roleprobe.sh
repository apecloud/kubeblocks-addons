#!/bin/bash

set -eo pipefail

pdAddr="http://127.0.0.1:2379"
extraArg=""
if [[ $KB_ENABLE_TLS_BETWEEN_COMPONENTS == "true" ]]; then
    pdAddr="https://127.0.0.1:2379"
    extraArg+="--cacert /etc/pki/cluster-tls/ca.pem --cert /etc/pki/cluster-tls/cert.pem --key /etc/pki/cluster-tls/key.pem"
fi

/pd-ctl -u $pdAddr $extraArg member 1>&2
# shellcheck disable=SC2086
LEADER_NAME=$(/pd-ctl -u $pdAddr $extraArg member | jq -r '.leader.name')
rtnCode=$?
if [[ $rtnCode != 0 ]]; then
    echo -n "unknown"
elif [ "$LEADER_NAME" == "$HOSTNAME" ]; then
    echo -n "leader"
else
    echo -n "follower"
fi
