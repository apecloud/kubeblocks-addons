#!/bin/bash
set -e  # Exit immediately if any command fails

# Load credentials from environment variables
MONGO_ROOT_USER="${MONGODB_USER}"
MONGO_ROOT_PASSWORD="${MONGODB_PASSWORD}"
MONGO_PORT="${MONGO_PORT:-27017}"

# Check if mongosh is available
CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`

# Check if environment variables are set
if [[ -z "$MONGO_ROOT_USER" || -z "$MONGO_ROOT_PASSWORD" ]]; then
    echo "ERROR: Required environment variables not set" >&2
    exit 1
fi

# Check if the pod is the first member of the replica set
# if [[ "${KB_POD_NAME: -1}" != "0" ]]; then
#     echo "INFO: This pod $KB_POD_NAME is not the first member of the replica set, exiting."
#     exit 1
# fi

# Check if balancer is enabled
balancer_state=$($CLIENT --quiet --port $MONGO_PORT --eval "sh.getBalancerState()")
if [[ "$balancer_state" == "false" ]]; then
    echo "INFO: Balancer is disabled, enabling it now..."
    $CLIENT --quiet --port $MONGO_PORT --eval "sh.startBalancer()"
else
    echo "INFO: Balancer is already enabled"
fi

# MongoDB connection and user creation command
$CLIENT --quiet --port $MONGO_PORT --eval "
try {
    // Switch to admin database
    const db = db.getSiblingDB('admin');
    
    // Check if user already exists
    if (db.getUser('$MONGO_ROOT_USER')) {
        print('[SKIPPED] User already exists');
        quit(0);
    }

    // Create root user with full privileges
    db.createUser({
        user: '$MONGO_ROOT_USER',
        pwd: '$MONGO_ROOT_PASSWORD',
        roles: [{ role: 'root', db: 'admin' }]
    });
    
    print('[SUCCESS] Root user created');
} catch (e) {
    print('[ERROR] ' + e.message);
    quit(1);
}"

echo "User: $MONGO_ROOT_USER , Password: $MONGO_ROOT_PASSWORD."