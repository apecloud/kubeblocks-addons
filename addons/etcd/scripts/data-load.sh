#!/bin/bash

set -ex 

default_template_conf="/etc/etcd/etcd.conf"
default_conf="$TMP_CONFIG_PATH"

cp "$default_template_conf" "$default_conf"
sed -i "s/^initial-cluster-state: 'new'/initial-cluster-state: 'existing'/g" "$default_conf"
