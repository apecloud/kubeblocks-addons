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

# From here on we are in a restore cluster. Start mongod first, apply the PBM
# storage config that prepareData wrote into the shared data volume, then start
# the temporary pbm-agent. This ordering prevents the agent from resyncing
# against the source cluster's prefix before the restore cluster's storage
# config is in place.
PBM_STORAGE_CONFIG_PATH="$MONGODB_ROOT/tmp/pbm_storage_config.yaml"
PBM_BACKUPFILE="$MONGODB_ROOT/tmp/mongodb_pbm.backup"
mkdir -p "$MONGODB_ROOT/tmp"
[ -f "$PBM_BACKUPFILE" ] || touch "$PBM_BACKUPFILE"

echo "INFO: Start mongodb for restore."
$process &

CLIENT=`mongosh --version >/dev/null 2>&1 && echo mongosh || echo mongo`
until $CLIENT --quiet --port $PORT --eval "db.adminCommand('ping')"; do
  echo "INFO: Waiting for mongod to be ready..."
  sleep 1
done

if [ -f "$PBM_STORAGE_CONFIG_PATH" ]; then
  echo "INFO: Applying prepared PBM storage config from $PBM_STORAGE_CONFIG_PATH"
  until pbm config --mongodb-uri "$PBM_MONGODB_URI" --file "$PBM_STORAGE_CONFIG_PATH"; do
    echo "ERROR: failed to apply PBM storage config, retrying..."
    sleep 2
  done
  echo "INFO: PBM storage config applied."
else
  echo "ERROR: Prepared PBM storage config not found at $PBM_STORAGE_CONFIG_PATH; restore cannot proceed."
  exit 1
fi

echo "INFO: Startup backup agent for restore."
pbm-agent-entrypoint >> $MONGODB_ROOT/tmp/pbm_agent_restore.log 2>&1 &

process_restore_signal "$process" "start"

process_restore_signal "$process" "end"
