#!/bin/sh

echo "start etcd..."

CUR_PATH=$(cd "$(dirname "$0")"; pwd)
# shellcheck source=./common.sh
source "${CUR_PATH}/common.sh"

# According to https://etcd.io/docs/v3.5/op-guide/configuration/ 
# etcd ignores command-line flags and environment variables if a configuration file is provided.
# need to copy the configuration file and modify it
export conf=/etc/etcd/etcd.conf
export tmpconf=$TMP_CONFIG_PATH

cp $conf $tmpconf

MY_PEER=${KB_POD_FQDN}${CLUSTER_DOMAIN}

# discovery config
sed -i "s#^name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#\(initial-advertise-peer-urls: https\?\).*#\\1://${MY_PEER}:2380#g" $tmpconf
sed -i "s#\(advertise-client-urls: https\?\).*#\\1://${MY_PEER}:2379#g" $tmpconf

# tls test: etcdctl --cacert=/etc/pki/tls/ca.crt --cert=/etc/pki/tls/tls.crt --key=/etc/pki/tls/tls.key member list

# member join reconfiguration
# sed -i "s#initial-cluster-state:.*#initial-cluster-state: existing#g" $tmpconf
cat $tmpconf

exec etcd --config-file $tmpconf