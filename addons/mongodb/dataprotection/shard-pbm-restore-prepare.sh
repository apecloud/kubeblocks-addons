#!/bin/bash
set -e
set -o pipefail

CLIENT=$(get_mongodb_client_name)
# shellcheck disable=SC2034
CLUSTER_MONGO="$CLIENT $(mongodb_tls_client_options "$CLIENT") --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGODB_USER -p $MONGODB_PASSWORD --quiet --eval"

# Wait for the mongos process to be ready
MAX_RETRIES=300
retry_count=0
while [ $retry_count -lt $MAX_RETRIES ]; do
    if mongodb_command_json "db.adminCommand({ ping: 1 })" >/dev/null; then
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
    if ! shard_exists=$(mongodb_query_json "db.getSiblingDB(\"config\").shards.findOne({ _id: \"$shardsvr_name\" }) !== null"); then
        echo "ERROR: Failed to check if shard $shardsvr_name exists." >&2
        exit 1
    fi
    case "$shard_exists" in
        true) return 0 ;;
        false) return 1 ;;
        *)
            echo "ERROR: Invalid shard existence result: $shard_exists" >&2
            exit 1
            ;;
    esac
}

# Check if sharding is ready
IFS="." read -r -a shardsvr_array <<< "$MONGODB_SHARD_REPLICA_SET_NAME_LIST"
shardsvr_count=${#shardsvr_array[@]}
for i in "${!shardsvr_array[@]}"; do
    # Get the part before "@" in new_shardsvr_array
    if [ "$shardsvr_count" -gt 1 ]; then
        shard_name="$CLUSTER_NAME-${shardsvr_array[i]%%@*}"
    else
        shard_name="${shardsvr_array[i]%%,*}"
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

balancer_status=$(mongodb_query_json "sh.getBalancerState()")
case "$balancer_status" in
    true) mongodb_command_json "db.adminCommand({ balancerStop: 1 })" >/dev/null ;;
    false) ;;
    *)
        echo "ERROR: Invalid balancer state: $balancer_status" >&2
        exit 1
        ;;
esac
echo "INFO: Balancer is disabled."
# Starting in MongoDB 6.0.3, automatic chunk splitting is not performed. This is because of balancing policy improvements.
# Auto-splitting commands still exist, but do not perform an operation.
# For details, see Balancing Policy Changes: https://www.mongodb.com/docs/manual/release-notes/6.0/#balancing-policy-changes

version=$(mongodb_query_json "db.version()" | jq -er 'select(type == "string")')
if [[ "$(echo -e "$version\n6.0.3" | sort -V | head -n1)" != "6.0.3" ]]; then
    $CLUSTER_MONGO "sh.disableAutoSplit()"
fi
echo "INFO: AutoSplit is disabled."
