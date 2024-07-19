#!/bin/bash
echo "start etcd..."
CUR_PATH="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./common.sh
source "${CUR_PATH}/common.sh"

# According to https://etcd.io/docs/v3.5/op-guide/configuration/ 
# etcd ignores command-line flags and environment variables if a configuration file is provided.
# need to copy the configuration file and modify it
export conf=/etc/etcd/etcd.conf
export tmpconf=/var/run/etcd/etcd.conf

cp $conf $tmpconf

# peer tls check
initial_advertise_peer_urls=$(sed -n 's/^initial-advertise-peer-urls: //p' $tmpconf)
peer_protocol=""
if echo "$initial_advertise_peer_urls" | grep -q "https" ; then
    peer_protocol="https"
else
    peer_protocol="http"
fi

# when a member joins, initial-cluster needs to be reset because configmap will not update automatically
MY_PEER=${KB_POD_FQDN}${CLUSTER_DOMAIN}
PEERS=""
DOMAIN=$KB_NAMESPACE".svc"$CLUSTER_DOMAIN
i=0 
while [ $i -lt $KB_REPLICA_COUNT ]; do
    if [ $i -ne 0 ]; then
        PEERS="$PEERS,";
    fi; 
    host=$(eval echo \$KB_"$i"_HOSTNAME)
    host=$host"."$DOMAIN
    replica_hostname=${KB_CLUSTER_COMP_NAME}-${i}
    PEERS="${PEERS}${replica_hostname}=${peer_protocol}://$host:2380"
    i=$(( i + 1))
done

# discovery config
sed -i "s#name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#\(initial-advertise-peer-urls: https\?\).*#\\1://${MY_PEER}:2380#g" $tmpconf
sed -i "s#\(advertise-client-urls: https\?\).*#\\1://${MY_PEER}:2379#g" $tmpconf

# tls config
sed -i "s#allowed-hostname:.*#allowed-hostname:#g" $tmpconf
# TEST: etcdctl --cacert=/etc/pki/tls/ca.crt --cert=/etc/pki/tls/tls.crt --key=/etc/pki/tls/tls.key member list

# member join reconfiguration
# sed -i "s#initial-cluster:.*#initial-cluster: ${PEERS}#g" $tmpconf
# sed -i "s#initial-cluster-state:.*#initial-cluster-state: existing#g" $tmpconf
cat $tmpconf

exec etcd --config-file $tmpconf