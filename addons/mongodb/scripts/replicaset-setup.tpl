#!/bin/sh
PORT=${SERVICE_PORT:-27017}
MONGODB_ROOT=${DATA_VOLUME:-/data/mongodb}
RPL_SET_NAME=$(echo $POD_NAME | grep -o ".*-");
RPL_SET_NAME=${RPL_SET_NAME%-};
mkdir -p $MONGODB_ROOT/db
mkdir -p $MONGODB_ROOT/logs
mkdir -p $MONGODB_ROOT/tmp
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

. "/scripts/mongodb-common.sh"

PBM_BACKUPFILE=$MONGODB_ROOT/tmp/mongodb_pbm.backup
process="mongod --bind_ip_all --port $PORT --replSet $CLUSTER_COMPONENT_NAME --config /etc/mongodb/mongodb.conf"
if [ ! -f $PBM_BACKUPFILE ]
then
  exec $process
  exit 0
fi

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint &

echo "INFO: Start mongodb for restore."
$process &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"
