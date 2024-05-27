#!/bin/bash
etcd_port=${ETCD_PORT:-'2379'}
etcd_server=${ETCD_SERVER:-'127.0.0.1'}

echo "Deleting all keys with prefix /vitess from Etcd server at ${etcd_server}:${etcd_port}..."
etcdctl --endpoints=http://${etcd_server}:${etcd_port} del /vitess --prefix

if [ $? -eq 0 ]; then
    echo "Successfully deleted all keys with prefix /vitess."
else
    echo "Failed to delete keys. Please check your Etcd server and try again."
    exit 1
fi