echo "start etcd..."

MY_PEER=${KB_POD_FQDN}${CLUSTER_DOMAIN}

export conf=/etc/etcd/etcd.conf
export tmpconf=/tmp/etcd/etcd.conf

cp $conf $tmpconf

sed -i "s#name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#\(initial-advertise-peer-urls: https\?\).*#\\1://${MY_PEER}:2380#g" $tmpconf
sed -i "s#\(advertise-client-urls: https\?\).*#\\1://${MY_PEER}:2379#g" $tmpconf

# TLS TEST: etcdctl --cacert=/etc/pki/tls/ca.crt --cert=/etc/pki/tls/tls.crt --key=/etc/pki/tls/tls.key member list 
cat $tmpconf

exec etcd --config-file $tmpconf