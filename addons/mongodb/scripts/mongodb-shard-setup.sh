#!/bin/bash
# shellcheck disable=SC2086

PORT=${SERVICE_PORT:-27017}
MONGODB_ROOT=${DATA_VOLUME:-/data/mongodb}
mkdir -p $MONGODB_ROOT/db
mkdir -p $MONGODB_ROOT/logs
mkdir -p $MONGODB_ROOT/tmp
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

process="mongod --bind_ip_all --port $PORT --replSet $CLUSTER_COMPONENT_NAME --config /etc/mongodb/mongodb.conf"
exec $process
