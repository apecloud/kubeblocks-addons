set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"
export PBM_MONGODB_URI="mongodb://$MONGODB_USER:$MONGODB_PASSWORD@$cfg_server_endpoints/?authSource=admin&replSetName=$CFG_SERVER_REPLICA_SET_NAME"

CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`
CLUSTER_MONGO="$CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGOS_USER -p $MONGOS_PASSWORD --quiet --eval"

# Wait for the mongos process to be ready
while true; do
    result=$($CLUSTER_MONGO "db.adminCommand({ ping: 1 })" 2>/dev/null)
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: Mongos is ready."
        break
    fi
    echo "INFO: Waiting for mongos to be ready..."
    sleep 1
done