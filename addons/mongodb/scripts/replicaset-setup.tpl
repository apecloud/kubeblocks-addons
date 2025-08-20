#!/bin/sh
PORT=${SERVICE_PORT:-27017}
MONGODB_ROOT=${DATA_VOLUME:-/data/mongodb}
RPL_SET_NAME=$(echo $POD_NAME | grep -o ".*-");
RPL_SET_NAME=${RPL_SET_NAME%-};
mkdir -p $MONGODB_ROOT/db
mkdir -p $MONGODB_ROOT/logs
mkdir -p $MONGODB_ROOT/tmp
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

# Allow the test framework to pass in a mock path to override the default /scripts.
SCRIPTS_BASE_PATH=${SCRIPTS_BASE_PATH:-/scripts}
. "$SCRIPTS_BASE_PATH/mongodb-common.sh"

PBM_BACKUPFILE=$MONGODB_ROOT/tmp/mongodb_pbm.backup
process="mongod --bind_ip_all --port $PORT --replSet $RPL_SET_NAME --config /etc/mongodb/mongodb.conf"
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
