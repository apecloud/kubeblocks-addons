#!/bin/bash

endpoints=${ETCD_SERVER:-'127.0.0.1:2379'}

ehco $endpoints

echo "Deleting all keys with prefix /vitess/${KB_CLUSTER_NAME} from Etcd server at ${endpoints}..."
etcdctl --endpoints=http://${endpoints} del /vitess/${KB_CLUSTER_NAME} --prefix

if [ $? -eq 0 ]; then
    echo "Successfully deleted all keys with prefix /vitess/$KB_CLUSTER_NAME."
else
    echo "Failed to delete keys. Please check your Etcd server and try again."
    exit 1
fi
