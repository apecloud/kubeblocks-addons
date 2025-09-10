#!/bin/sh

{{- $mongodb_root := getVolumePathByName ( index $.podSpec.containers 0 ) "data" }}
{{- $mongodb_port_info := getPortByName ( index $.podSpec.containers 0 ) "mongodb" }}

# require port
{{- $mongodb_port := 27017 }}
{{- if $mongodb_port_info }}
{{- $mongodb_port = $mongodb_port_info.containerPort }}
{{- end }}

PORT={{ $mongodb_port }}
MONGODB_ROOT={{ $mongodb_root }}
mkdir -p $MONGODB_ROOT/db
mkdir -p $MONGODB_ROOT/logs
mkdir -p $MONGODB_ROOT/tmp
export PATH=$MONGODB_ROOT/tmp/bin:$PATH

cp /etc/mongodb/keyfile $MONGODB_ROOT/keyfile
chmod 600 $MONGODB_ROOT/keyfile

. "/scripts/mongodb-common.sh"

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
CLIENT=`mongosh --version 1>/dev/null&&echo mongosh||echo mongo`
process="mongod --bind_ip_all --port $PORT --replSet $KB_CLUSTER_COMP_NAME --config /etc/mongodb/mongodb.conf"
if [ ! -f $PBM_BACKUPFILE ]
then
  echo "INFO: Do not need to restore."
  exec $process
  exit 0
fi

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint &

echo "INFO: Start mongodb for restore."
$process &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"