#!/bin/bash

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

# Root account's credential secret is a sub-resource of the config server component and cannot be used for shard component pre-terminate jobs.
# This is because if the config server component is deleted before shard components, the root credential secret becomes unavailable and pre-terminate job pods cannot be created.
# And we can't control the order of deletion of components when we use `cluster.spec.shardingSpec` for now. So we use shard components' own cluster admin credentials.

# Check if cluster admin user already exists and has correct privileges
CLUSTER_ADMIN_CHECK=$($CLUSTER_MONGO "db.getSiblingDB('admin').getUser('$CLUSTER_ADMIN_USER')")

if [ -z "$CLUSTER_ADMIN_CHECK" ] || [ "$CLUSTER_ADMIN_CHECK" == "null" ]; then
    echo "Creating cluster admin user..."
    $CLUSTER_MONGO "db.getSiblingDB('admin').createUser({
        user: '$CLUSTER_ADMIN_USER',
        pwd: '$CLUSTER_ADMIN_PASSWORD',
        roles: ['root']
    })"
else
    echo "Checking cluster admin user privileges and password..."
    $CLUSTER_MONGO "const user = db.getSiblingDB('admin').getUser('$CLUSTER_ADMIN_USER');
        if (!user.roles.some(role => role.role === 'root')) {
            db.getSiblingDB('admin').grantRolesToUser('$CLUSTER_ADMIN_USER', ['root']);
        }
        db.getSiblingDB('admin').updateUser('$CLUSTER_ADMIN_USER', { pwd: '$CLUSTER_ADMIN_PASSWORD' });
    "
fi

# Check if need to enable balancer
if [ "$MONGODB_BALANCER_ENABLED" == "false" ]; then
    $CLUSTER_MONGO "sh.stopBalancer()"
    echo "Balancer is disabled."
else
    $CLUSTER_MONGO "sh.startBalancer()"
    echo "Balancer is enabled."
fi