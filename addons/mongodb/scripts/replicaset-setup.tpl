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

# Restore from datafile
BACKUPFILE=$MONGODB_ROOT/db/mongodb.backup
PORT_FOR_RESTORE=27027
if [ -f $BACKUPFILE ]
then
  CLIENT=`mongosh --version >/dev/null&&echo mongosh||echo mongo`
  mongod --bind_ip_all --port $PORT_FOR_RESTORE --dbpath $MONGODB_ROOT/db --directoryperdb --logpath $MONGODB_ROOT/logs/mongodb.log  --logappend --pidfilepath $MONGODB_ROOT/tmp/mongodb.pid&
  until $CLIENT --quiet --port $PORT_FOR_RESTORE --eval "print('restore process is ready')"; do sleep 1; done
  PID=`cat $MONGODB_ROOT/tmp/mongodb.pid`

  $CLIENT --quiet --port $PORT_FOR_RESTORE local --eval "db.system.replset.deleteOne({})"
  $CLIENT --quiet --port $PORT_FOR_RESTORE local --eval "db.system.replset.find()"
  $CLIENT --quiet --port $PORT_FOR_RESTORE admin --eval 'db.dropUser("root", {w: "majority", wtimeout: 4000})' || true
  # used for pbm
  $CLIENT --quiet --port $PORT_FOR_RESTORE admin --eval 'db.dropRole("anyAction", {w: "majority", wtimeout: 4000})' || true
  kill $PID
  wait $PID
  echo "INFO: restore set-up configuration successfully."
  rm $BACKUPFILE
fi

# Restore from pbm
PBM_BACKUPFILE=$MONGODB_ROOT/tmp/mongodb_pbm.backup
process="mongod --bind_ip_all --port $PORT --replSet $RPL_SET_NAME --config /etc/mongodb/mongodb.conf"
if [ ! -f $PBM_BACKUPFILE ]
then
  exec $process
  exit 0
fi

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint > $MONGODB_ROOT/tmp/pbm-agent.log 2>&1 &

echo "INFO: Start mongodb for restore."
$process &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"
