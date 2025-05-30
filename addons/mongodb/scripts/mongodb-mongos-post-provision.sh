#!/bin/bash

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
CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`
CLUSTER_MONGO="$CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGOS_USER -p $MONGOS_PASSWORD --quiet --eval"

# Wait for the mongos process to be ready
while true; do
    result=$($CLUSTER_MONGO "db.adminCommand({ ping: 1 })")
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: Mongos is ready."
        break
    fi
    echo "INFO: Waiting for mongos to be ready..."
    sleep 1
done

# Check if root user already exists and has correct privileges
ROOT_CHECK=$($CLUSTER_MONGO "db.getSiblingDB('admin').getUser('$CLUSTER_ADMIN_USER')")

if [ -z "$ROOT_CHECK" ] || [ "$ROOT_CHECK" == "null" ]; then
    echo "Creating root user..."
    $CLUSTER_MONGO "db.getSiblingDB('admin').createUser({
        user: '$CLUSTER_ADMIN_USER',
        pwd: '$CLUSTER_ADMIN_PASSWORD',
        roles: ['root']
    })"
else
    echo "Checking root user privileges and password..."
    $CLUSTER_MONGO "const user = db.getSiblingDB('admin').getUser('$CLUSTER_ADMIN_USER');
        if (!user.roles.some(role => role.role === 'root')) {
            db.getSiblingDB('admin').grantRolesToUser('$CLUSTER_ADMIN_USER', ['root']);
        }
        db.getSiblingDB('admin').updateUser('$CLUSTER_ADMIN_USER', { pwd: '$CLUSTER_ADMIN_PASSWORD' });
    "
fi