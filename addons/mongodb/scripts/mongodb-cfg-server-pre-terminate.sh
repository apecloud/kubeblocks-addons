#!/bin/bash
set -e  # Exit immediately if any command fails
CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`
CLUSTER_CFG_SERVER="$CLIENT --host $CFG_SERVER_INTERNAL_HOST --port $CFG_SERVER_INTERNAL_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval"

shards_exist() {
    count=$($CLUSTER_CFG_SERVER "db.getSiblingDB('config').shards.count()")
    if [ "$count" = "0" ]; then
        return 1
    else
        return 0
    fi
}

while shards_exist; do
    echo "Waiting for shards to be terminated..."
    sleep 2
done