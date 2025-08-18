#!/bin/bash
# shellcheck disable=SC2086

PORT=${SERVICE_PORT:-27017}
MONGODB_ROOT=${DATA_VOLUME:-/data/mongodb}
mkdir -p $MONGODB_ROOT/db
mkdir -p $MONGODB_ROOT/logs
mkdir -p $MONGODB_ROOT/tmp
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

. "/scripts/mongodb-common.sh"

process="mongod --bind_ip_all --port $PORT --replSet $CLUSTER_COMPONENT_NAME --config /etc/mongodb/mongodb.conf"
boot_or_enter_restore "$process"

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint &

echo "INFO: Start mongodb for restore."
$process &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"
