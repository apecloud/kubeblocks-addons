#!/bin/bash

# ZOOKEEPER_POD_FQDN_LIST eg:  zk-zookeeper-0.zk-zookeeper-headless.default.svc.cluster.local,zk-zookeeper-1.zk-zookeeper-headless.default.svc.cluster.local
zk_member_fqdns=${ZOOKEEPER_POD_FQDN_LIST//,/ }
for member in $zk_member_fqdns; do
    # if member contains CURRENT_POD_NAME
    if [[ $member == *"$KB_POD_NAME"* ]]; then
        zk_current_member_fqdn=$member
    fi
done

if [ -z "$zk_current_member_fqdn" ]; then
    echo "ERROR: Could not find current pod FQDN in ZOOKEEPER_POD_FQDN_LIST"
    exit 1
else
    echo "Current pod FQDN: $zk_current_member_fqdn"
    current_member_index=${KB_POD_NAME##*-}
    zkCli.sh << EOF
        addauth digest $ZK_ADMIN_USER:$ZK_ADMIN_PASSWORD
        reconfig -add server.${current_member_index}=$zk_current_member_fqdn:2888:3888:participant;2181
EOF
fi