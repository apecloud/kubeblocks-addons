#!/bin/sh

echo "start etcd..."

# According to https://etcd.io/docs/v3.5/op-guide/configuration/ 
# etcd ignores command-line flags and environment variables if a configuration file is provided.
# need to copy the configuration file and modify it
export conf=/etc/etcd/etcd.conf
export tmpconf=$TMP_CONFIG_PATH

cp $conf $tmpconf

MY_PEER=${KB_POD_FQDN}${CLUSTER_DOMAIN}

if [ ! -z "$PEER_ENDPOINT" ]; then
  echo "loadBalancer mode, need to adapt pod FQDN to balance IP"
  endpoints=$(echo "$PEER_ENDPOINT" | tr ',' '\n')
  myEndpoint=$(echo "$endpoints" | grep $HOSTNAME)
  if [ -z "$myEndpoint" ]; then
    echo "WARNING: host name not found in peer endpoints, please set podService to true if you want to bootstrap multi-cluster etcd"
  else
    # e.g.1 etcd-cluster-etcd-0
    # e.g.2 etcd-cluster-etcd-0:127.0.0.1
    if echo "$myEndpoint" | grep -q ":"; then
      MY_PEER=$(echo "$myEndpoint" | cut -d: -f2)
    else
      MY_PEER=$myEndpoint
    fi
  fi
fi

# discovery config
sed -i "s#^name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#\(initial-advertise-peer-urls: https\?\).*#\\1://${MY_PEER}:2380#g" $tmpconf
sed -i "s#\(advertise-client-urls: https\?\).*#\\1://${MY_PEER}:2379#g" $tmpconf

# tls test: etcdctl --cacert=/etc/pki/tls/ca.crt --cert=/etc/pki/tls/tls.crt --key=/etc/pki/tls/tls.key member list

# member join reconfiguration
# sed -i "s#initial-cluster-state:.*#initial-cluster-state: existing#g" $tmpconf
cat $tmpconf

exec etcd --config-file $tmpconf