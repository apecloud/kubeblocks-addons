echo "start etcd..."

MY_PEER=${KB_POD_FQDN}${CLUSTER_DOMAIN}

# ===================== dependency & tls file generation START ===================== 
export http_proxy=http://172.30.112.1:6000
export https_proxy=http://172.30.112.1:6000
apt update
apt install openssl
apt install -y curl

rm -f /tmp/cfssl*

curl -L https://pkg.cfssl.org/R1.2/cfssl_linux-amd64 -o /tmp/cfssl
chmod +x /tmp/cfssl
mv /tmp/cfssl /usr/local/bin/cfssl

curl -L https://pkg.cfssl.org/R1.2/cfssljson_linux-amd64 -o /tmp/cfssljson
chmod +x /tmp/cfssljson
mv /tmp/cfssljson /usr/local/bin/cfssljson

/usr/local/bin/cfssl version
/usr/local/bin/cfssljson -h

# KB TLS FILES: /etc/pki/tls
# ca.crt(root CA)  tls.crt(self sign CA public key)  tls.key (self sign CA private key)
# ca.crt==tls.crt

export http_proxy=
export https_proxy=

# reference http://play.etcd.io/install
# use component root self sign CA generate pod CA
rm -rf /tmp/pki && mkdir -p /tmp/pki
cp /etc/pki/tls /tmp/pki -r
export CAPATH=/tmp/pki/tls
echo "gencert.json"
# cert-generation configuration
cat > ${CAPATH}/etcd-gencert.json <<EOF
{
  "signing": {
    "default": {
        "usages": [
          "signing",
          "key encipherment",
          "server auth",
          "client auth"
        ],
        "expiry": "876000h"
    }
  }
}
EOF

echo "ca-csr.json"

cat > ${CAPATH}/${HOSTNAME}-ca-csr.json <<EOF
{
  "key": {
    "algo": "rsa",
    "size": 2048
  },
  "names": [
    {
      "O": "ApeCloud",
      "OU": "etcd-addon",
      "L": "Hang Zhou",
      "C": "CN"
    }
  ],
  "CN": "etcd peer",
  "hosts": [
    "127.0.0.1",
    "localhost",
    "*.${KB_CLUSTER_COMP_NAME}-headless.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}"
  ]
}
EOF

echo "cert.json"
cfssl gencert \
  --ca ${CAPATH}/tls.crt \
  --ca-key ${CAPATH}/tls.key \
  --config ${CAPATH}/etcd-gencert.json \
  ${CAPATH}/${HOSTNAME}-ca-csr.json | cfssljson --bare ${CAPATH}/${HOSTNAME}

# verify
openssl x509 -in ${CAPATH}/${HOSTNAME}.pem -text -noout

# ===================== dependency & tls file generation END ===================== 

ls -al /etc/etcd

export conf=/etc/etcd/etcd.conf
export tmpconf=/tmp/etcd/etcd.conf

cp $conf $tmpconf

sed -i "s#name:.*#name: ${HOSTNAME}#g" $tmpconf
sed -i "s#initial-advertise-peer-urls:.*#initial-advertise-peer-urls: https:\/\/${MY_PEER}:2380#g" $tmpconf
sed -i "s#advertise-client-urls:.*#advertise-client-urls: https:\/\/${MY_PEER}:2379#g" $tmpconf

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

# TEST: etcdctl --cacert=/tmp/pki/tls/ca.crt --cert=/tmp/pki/tls/etcd-cluster-etcd-0.pem --key=/tmp/pki/tls/etcd-cluster-etcd-0-key.pem member list 
cat $tmpconf

exec etcd --config-file $tmpconf

# PEERS=""
# MY_PEER=""

# echo ${PEER_ENDPOINT}
# if [ -z "${PEER_ENDPOINT}" ]; then
#     DOMAIN=$KB_NAMESPACE".svc{{ .Values.clusterDomain }}"
#     SUBDOMAIN=${KB_CLUSTER_COMP_NAME}-headless
#     replicas=$(eval echo ${KB_POD_LIST} | tr ',' '\n')
#     for replica in ${replicas}; do
#         host=${replica}.${SUBDOMAIN}.${DOMAIN}
#         PEERS="${PEERS}${replica}=http://${host}:2380,"
#     done
#     PEERS=${PEERS%,}
#     MY_PEER=$KB_POD_FQDN{{ .Values.clusterDomain }}
# else
#     my_id=$(eval echo ${KB_POD_NAME} | grep -oE "[0-9]+\$")
#     endpoints=$(eval echo ${PEER_ENDPOINT} | tr ',' '\n')
#     for endpoint in ${endpoints}; do
#         host=$(eval echo ${endpoint} | cut -d ':' -f 1)
#         ip=$(eval echo ${endpoint} | cut -d ':' -f 2)
#         host_id=$(eval echo ${host} | grep -oE "[0-9]+\$")
#         hostname=${KB_CLUSTER_COMP_NAME}-${host_id}
#         PEERS="${PEERS}${hostname}=http://${ip}:2380,"
#         if [ "${my_id}" = "${host_id}" ]; then
#             MY_PEER=${ip}
#         fi
#     done
#     PEERS=${PEERS%,}
# fi
# echo "peers: ${PEERS}, my-peer: ${MY_PEER}"

# exec etcd --name ${HOSTNAME} \
# --experimental-initial-corrupt-check=true \
# --listen-peer-urls https://0.0.0.0:2380 \
# --listen-client-urls http://0.0.0.0:2379 \
# --advertise-client-urls http://${MY_PEER}:2379 \
# --initial-advertise-peer-urls https://${MY_PEER}:2380 \
# --initial-cluster ${PEERS} \
# --data-dir /var/run/etcd/default.etcd \
# --auto-tls --peer-auto-tls
