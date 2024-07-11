echo "start etcd..."


export conf=/etc/etcd/etcd.conf
export tmpconf=/tmp/etcd/etcd.conf

cp $conf $tmpconf

# peer tls check
initial_advertise_peer_urls=$(sed -n 's/^initial-advertise-peer-urls: //p' $tmpconf)
peer_protocol=""
if echo "$initial_advertise_peer_urls" | grep -q "https" ; then
    peer_protocol="https"
else
    peer_protocol="http"
fi

# member join need to reset initial-cluster, cause configmap will not be updated when environment variables change
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
    hostname=${KB_CLUSTER_COMP_NAME}-${i}
    PEERS="$PEERS$hostname=${peer_protocol}://$host:2380"
    i=$(( i + 1))
done

sed -i "s#name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#\(initial-advertise-peer-urls: https\?\).*#\\1://${MY_PEER}:2380#g" $tmpconf
sed -i "s#\(advertise-client-urls: https\?\).*#\\1://${MY_PEER}:2379#g" $tmpconf
sed -i "s#initial-cluster:.*#initial-cluster: ${PEERS}#g" $tmpconf

# hscale member join
# sed -i "s#initial-cluster-state:.*#initial-cluster-state: existing#g" $tmpconf

cat $tmpconf
exec etcd --config-file $tmpconf

# TLS TEST: etcdctl --cacert=/etc/pki/tls/ca.crt --cert=/etc/pki/tls/tls.crt --key=/etc/pki/tls/tls.key member list 