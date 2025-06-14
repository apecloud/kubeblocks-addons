#!/bin/bash

client_path=$(whereis mongosh | awk '{print $2}')
CLIENT="mongosh"
if [ -z "$client_path" ]; then
    CLIENT="mongo"
fi
# Wait for the local mongodb to be ready
while true; do
    result=$($CLIENT --port $KB_SERVICE_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval "db.adminCommand({ ping: 1 })" 2>/dev/null)
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: Local MongoDB is ready."
        break
    fi
    echo "INFO: Waiting for local MongoDB to be ready..."
    sleep 1
done

# Wait for the mongos process to be ready
while true; do
    result=$($CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval "db.adminCommand({ ping: 1 })" 2>/dev/null)
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: mongos is ready."
        break
    fi
    echo "INFO: Waiting for mongos to be ready..."
    sleep 1
done

# hack to make sure the backup agent can run without storage checking, backup storage will be changed by backup or restore workloads later.
echo "latest" > /tmp/mongodb/backups/.pbm.init

if [ "$MONGODB_CLUSTER_ROLE" == "configsvr" ]; then
    # Get the cluster admin credentials from environment variables
    CLUSTER_ADMIN_USER=""
    CLUSTER_ADMIN_PASSWORD=""
    for env_var in $(env | grep -E '^MONGODB_ADMIN_USER'); do
        CLUSTER_ADMIN_USER="${env_var#*=}"
        if [ -z "$CLUSTER_ADMIN_USER" ]; then
            continue
        fi
        break
    done
    for env_var in $(env | grep -E '^MONGODB_ADMIN_PASSWORD'); do
        CLUSTER_ADMIN_PASSWORD="${env_var#*=}"
        if [ -z "$CLUSTER_ADMIN_PASSWORD" ]; then
            continue
        fi
        break
    done

    if [ -z "$CLUSTER_ADMIN_USER" ] || [ -z "$CLUSTER_ADMIN_PASSWORD" ]; then
        echo "ERROR: MONGODB_ADMIN_USER or MONGODB_ADMIN_PASSWORD is not set." >&2
        exit 1
    fi

    export PBM_AGENT_MONGODB_USERNAME="$CLUSTER_ADMIN_USER"
    export PBM_AGENT_MONGODB_PASSWORD="$CLUSTER_ADMIN_PASSWORD"
    export PBM_MONGODB_URI="mongodb://$PBM_AGENT_MONGODB_USERNAME:$PBM_AGENT_MONGODB_PASSWORD@localhost:$KB_SERVICE_PORT/?authSource=admin"
fi

exec pbm-agent-entrypoint