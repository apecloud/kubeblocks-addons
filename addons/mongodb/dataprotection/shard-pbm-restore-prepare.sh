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

check_shard_exists() {
    # check if the shard exists in the config database
    local shardsvr_name=$1
    local shard_exists
    shard_exists=$($CLUSTER_MONGO "db.getSiblingDB(\"config\").shards.find({ _id: \"$shardsvr_name\" })")
    if [ -n "$shard_exists" ]; then
        return 0 # true
    else
        return 1
    fi
}

# Check if sharding is ready
IFS="." read -r -a shardsvr_array <<< "$MONGODB_SHARD_REPLICA_SET_NAME_LIST"
shardsvr_count=${#shardsvr_array[@]}
for i in "${!shardsvr_array[@]}"; do
    # Get the part before "@" in new_shardsvr_array
    if [ $shardsvr_count -gt 1 ]; then
        shard_name="$CLUSTER_NAME-${shardsvr_array[i]%%@*}"
    else
        shard_name="${shardsvr_array[i]%%,*}"
        shard_name="${shard_name%-*}"
    fi
    retry_count=0
    while ! check_shard_exists "$shard_name"; do
        echo "INFO: Shard $shard_name does not exist, retrying... (attempt $((retry_count+1))/$MAX_RETRIES)"
        retry_count=$((retry_count+1))
        if [ $retry_count -ge $MAX_RETRIES ]; then
            echo "ERROR: Shard $shard_name failed to become ready after $MAX_RETRIES attempts." >&2
            exit 1
        fi
        sleep 2
    done
done

original_balance_status=$($CLUSTER_MONGO "sh.getBalancerState()")
if [ "$original_balance_status" = "true" ]; then
    $CLUSTER_MONGO "sh.stopBalancer()"
fi
echo "INFO: Balancer is disabled."
# Starting in MongoDB 6.0.3, automatic chunk splitting is not performed. This is because of balancing policy improvements. 
# Auto-splitting commands still exist, but do not perform an operation. 
# For details, see Balancing Policy Changes: https://www.mongodb.com/docs/manual/release-notes/6.0/#balancing-policy-changes

version=$($CLUSTER_MONGO "db.version()")
if [[ "$(echo -e "$version\n6.0.3" | sort -V | head -n1)" != "6.0.3" ]]; then
    $CLUSTER_MONGO "sh.disableAutoSplit()"
fi
echo "INFO: AutoSplit is disabled."
