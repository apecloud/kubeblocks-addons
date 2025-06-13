#!/bin/bash
set -e
set -o pipefail

client_path=$(whereis mongosh | awk '{print $2}')
CLIENT="mongosh"
if [ -z "$client_path" ]; then
    CLIENT="mongo"
fi
CLUSTER_MONGO="$CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval"

# Wait for the mongos process to be ready
MAX_RETRIES=300
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    result=$($CLUSTER_MONGO "db.adminCommand({ ping: 1 })" 2>/dev/null)
    if [[ "$result" == *"ok"* ]]; then
        echo "INFO: Mongos is ready."
        break
    fi
    echo "INFO: Waiting for mongos to be ready... (attempt $((retry_count+1))/$MAX_RETRIES)"
    retry_count=$((retry_count+1))
    sleep 2
done

if [ $retry_count -eq $MAX_RETRIES ]; then
    echo "ERROR: Mongos failed to become ready after $MAX_RETRIES attempts." >&2
    exit 1
fi

# Check if need to enable balancer
if [ "$MONGODB_BALANCER_ENABLED" = "true" ]; then
    $CLUSTER_MONGO "sh.startBalancer()"
    echo "INFO: Balancer is enabled."
fi

# Starting in MongoDB 6.0.3, automatic chunk splitting is not performed. This is because of balancing policy improvements. 
# Auto-splitting commands still exist, but do not perform an operation. 
# For details, see Balancing Policy Changes: https://www.mongodb.com/docs/manual/release-notes/6.0/#balancing-policy-changes

version=$($CLUSTER_MONGO "db.version()")
if [[ "$(echo -e "$version\n6.0.3" | sort -V | head -n1)" != "6.0.3" ]]; then
    $CLUSTER_MONGO "sh.enableAutoSplit()"
    echo "INFO: AutoSplit is enabled."
fi