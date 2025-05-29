#!/bin/bash
set -e
MONGODB_REPLICA_SET_NAME=$KB_CLUSTER_COMP_NAME

CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`
CLUSTER_MONGO="$CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGOS_USER -p $MONGOS_PASSWORD --quiet --eval"

generate_endpoints() {
    local fqdns=$1
    local port=$2

    if [ -z "$fqdns" ]; then
        echo "ERROR: No FQDNs provided for config server endpoints." >&2
        exit 1
    fi

    IFS=',' read -ra fqdn_array <<< "$fqdns"
    local endpoints=()

    for fqdn in "${fqdn_array[@]}"; do
        trimmed_fqdn=$(echo "$fqdn" | xargs)
        if [[ -n "$trimmed_fqdn" ]]; then
            endpoints+=("${trimmed_fqdn}:${port}")
        fi
    done

    IFS=','; echo "${endpoints[*]}"
}

# Check if the pod is the first member of the replica set
check_if_first_member() {
    if [[ "${KB_POD_NAME: -1}" != "0" ]]; then
        echo "INFO: This pod $KB_POD_NAME is not the first member of the replica set, exiting."
        exit 0
    fi
}

wait_for_mongos() {
    # Wait for the mongos process to be ready
    while true; do
        result=$($CLUSTER_MONGO "db.adminCommand({ ping: 1 })")
        if [[ "$result" == *"ok"* ]]; then
            echo "INFO: Mongos is ready."
            break
        fi
        sleep 2
    done
}


check_shard_exists() {
    # Check if the shard exists in the config database
    local shard_exists
    shard_exists=$($CLUSTER_MONGO "db.getSiblingDB(\"config\").shards.find({ _id: \"$MONGODB_REPLICA_SET_NAME\" })")
    if [ -n "$shard_exists" ]; then
        return 0 # true
    else
        return 1
    fi
}

initialize_or_scale_out_mongodb_shard() {
    wait_for_mongos
    # check_if_first_member

    # Check if the shard exists
    if check_shard_exists; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME already exists, skipping initialization."
        exit 0
    fi

    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, initializing..."
    pod_endpoints=$(generate_endpoints "$MONGODB_POD_FQDN_LIST" "$KB_SERVICE_PORT")
    echo "INFO: Adding shard $MONGODB_REPLICA_SET_NAME with endpoints: $pod_endpoints"
    $CLUSTER_MONGO "sh.addShard(\"$MONGODB_REPLICA_SET_NAME/$pod_endpoints\")"
}

get_remove_shard_status() {
    # Execute the removeShard command and capture its JSON output
    local result
    result=$($CLUSTER_MONGO "EJSON.stringify(db.adminCommand( { removeShard: \"$MONGODB_REPLICA_SET_NAME\" } ))")
    echo "$result"
}

get_remove_shard_state() {
    local result=$1
    # Parse and log the state using jq
    local state
    state=$(echo "$result" | jq -r '.state')
    # Return the state as the function output
    echo "$state"
}

delete_or_scale_in_mongodb_shard() {
    # Check if the shard is scaling in
    if [[ $KB_CLUSTER_COMPONENT_IS_SCALING_IN != "true" ]]; then
        # Check if shard exists in config server
        if check_shard_exists; then
            $CLUSTER_MONGO "db.getSiblingDB('config').shards.deleteOne({ _id: '$MONGODB_REPLICA_SET_NAME' })"
            echo "INFO: Shard $MONGODB_REPLICA_SET_NAME record deleted from config server."
        else
            echo "INFO: Shard $MONGODB_REPLICA_SET_NAME record not found in config server."
        fi
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME is not scaling in, skipping scale-in."
        exit 0
    fi

    wait_for_mongos

    # check_if_first_member
    if ! check_shard_exists; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, skipping scale-in."
        exit 0
    fi

    balance_status=$($CLUSTER_MONGO "sh.getBalancerState()")
    if [ "$balance_status" = "false" ]; then
        $CLUSTER_MONGO "sh.startBalancer()"
    fi

    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME exists, scaling in..."
    # Remove the shard and wait until the state is 'completed'
    moved_primary="false"
    while true; do

        if ! check_shard_exists; then
            echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, exiting."
            exit 0
        fi

        status_json=$(get_remove_shard_status)
        echo "INFO: Remove shard status: $status_json"
        state=$(get_remove_shard_state "$status_json")
        echo "INFO: Current state of shard $MONGODB_REPLICA_SET_NAME is $state"
        if [ "$state" = "completed" ]; then
            break
        elif [ "$state" = "ongoing" ]; then
            remaining_jumboChunks=$(echo "$status_json" | jq -r '.remaining.jumboChunks')
            if [ "$remaining_jumboChunks" -gt 0 ]; then
                echo "INFO: $remaining_jumboChunks jumbo chunks remaining, please clear jumbo chunks before removing the shard."
                exit 1
            fi

            remaining_chunks=$(echo "$status_json" | jq -r '.remaining.chunks')
            echo "INFO: $remaining_chunks chunks remaining."
            if [ "$remaining_chunks" -eq 0 ]; then
                if [ "$moved_primary" = "true" ]; then
                    echo "INFO: waiting for moving primary to complete..."
                    continue
                fi
                dbs_to_move=$(echo "$status_json" | jq -r '.dbsToMove[]')
                note=$(echo "$status_json" | jq -r '.note')
                echo "INFO: $note moving primary for databases: $dbs_to_move"
                for db in $dbs_to_move; do
                    echo "INFO: Database '$db' is scheduled for movePrimary..."
                    if [ -z "$TARGET_SHARD" ]; then
                        echo "INFO: TARGET_SHARD not defined, selecting a random available shard..."
                        TARGET_SHARD=$($CLUSTER_MONGO "JSON.stringify(db.getSiblingDB('config').shards.find({ _id: { \$ne: '$MONGODB_REPLICA_SET_NAME' } }).toArray())" | jq -r '.[]._id' | shuf -n 1)
                        if [ -z "$TARGET_SHARD" ]; then
                            echo "ERROR: No available shard found for moving primary for database '$db'."
                            exit 1
                        fi
                        echo "INFO: Selected TARGET_SHARD: $TARGET_SHARD"
                    fi
                    $CLUSTER_MONGO "db.adminCommand({ movePrimary: \"$db\", to: \"$TARGET_SHARD\" })"
                done
                moved_primary="true"
                echo "INFO: waiting for moving primary to complete..."
                continue
            else
                echo "INFO: $remaining_chunks chunks are still being migrated, waiting..."
            fi
        fi
        sleep 2
    done
    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME has been successfully removed."
}

# main
if [ $# -eq 1 ]; then
  case $1 in
  --help)
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  --help                show help information"
    echo "  --post-provision      initialize or scale out mongodb shard"
    echo "  --pre-terminate       stop or scale in mongodb shard"
    exit 0
    ;;
  --post-provision)
    initialize_or_scale_out_mongodb_shard
    exit 0
    ;;
  --pre-terminate)
    # avoid config server component and its secrets being deleted before the shard is removed,
    # so we execute pre-terminate script in the first member pod.
    # check_if_first_member
    delete_or_scale_in_mongodb_shard
    exit 0
    ;;
  *)
    echo "Error: invalid option '$1'"
    exit 1
    ;;
  esac
fi