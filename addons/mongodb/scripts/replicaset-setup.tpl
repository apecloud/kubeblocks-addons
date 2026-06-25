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

# For restore clusters, ensure the PBM restore flag exists before starting mongod.
# The sidecar mongodb-backup-agent waits while this flag is present, so creating
# it here prevents the backup-agent from starting a pbm-agent that lacks the
# mongod binary required for physical restore.
PBM_BACKUPFILE=$MONGODB_ROOT/tmp/mongodb_pbm.backup
cluster_json=$(kubectl get clusters.apps.kubeblocks.io ${CLUSTER_NAME} -n ${CLUSTER_NAMESPACE} -o json 2>/dev/null) || true
if is_restore_cluster "$cluster_json"; then
  mkdir -p "$MONGODB_ROOT/tmp"
  touch "$PBM_BACKUPFILE"
fi

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
process="mongod --bind_ip_all --port $PORT --replSet $RPL_SET_NAME --config /etc/mongodb/mongodb.conf"
if [ ! -f $PBM_BACKUPFILE ]
then
  exec $process
  exit 0
fi

# Restore cluster: start mongod first, apply the PBM storage config that the
# prepareData job wrote into the shared data volume, then start the temporary
# pbm-agent. This ordering prevents any pbm-agent from resyncing against the
# source cluster's prefix before the restore cluster's storage config is in
# place, which caused global PBM lock contention.
echo "INFO: Start mongodb for restore."
$process &

CLIENT=`mongosh --version >/dev/null 2>&1 && echo mongosh || echo mongo`
until $CLIENT --quiet --port $PORT --eval "db.adminCommand('ping')"; do
  echo "INFO: Waiting for mongod to be ready..."
  sleep 1
done

PBM_STORAGE_CONFIG_PATH="$MONGODB_ROOT/tmp/pbm_storage_config.yaml"
if [ -f "$PBM_STORAGE_CONFIG_PATH" ]; then
  echo "INFO: Applying prepared PBM storage config from $PBM_STORAGE_CONFIG_PATH"
  pbm config --mongodb-uri "$PBM_MONGODB_URI" --file "$PBM_STORAGE_CONFIG_PATH"
  echo "INFO: PBM storage config applied."
else
  echo "WARN: Prepared PBM storage config not found at $PBM_STORAGE_CONFIG_PATH; falling back to post-ready job configuration."
fi

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint >> $MONGODB_ROOT/tmp/pbm_agent_restore.log 2>&1 &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"
