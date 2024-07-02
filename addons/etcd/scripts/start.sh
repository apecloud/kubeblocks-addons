echo "start etcd..."

MY_PEER=${KB_POD_FQDN}${CLUSTER_DOMAIN}

ls -al /etc/etcd

export conf=/etc/etcd/etcd.conf
export tmpconf=/tmp/etcd/etcd.conf

cp $conf $tmpconf

sed -i "s#name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#initial-advertise-peer-urls:.*#initial-advertise-peer-urls: http:\/\/${MY_PEER}:2380#g" $tmpconf
sed -i "s#advertise-client-urls:.*#advertise-client-urls: http:\/\/${MY_PEER}:2379#g" $tmpconf

certauths=$(grep -oP 'client-cert-auth: \K.*' $tmpconf)
tls_set=false
echo $certauths

for certauth in $certauths; do
    if [ "$certauth" = "true" ]; then
        tls_set=true
    fi
done

if $tls_set; then
    sed -i "s/http:/https:/g" $tmpconf
    echo "tls enable, replace http to https"
else
    echo "tls not set"
fi

# TEST: etcdctl --cacert=/etc/pki/tls/ca.crt --cert=/etc/pki/tls/tls.crt --key=/etc/pki/tls/tls.key member list 
cat $tmpconf

exec etcd --config-file $tmpconf