#!/bin/bash

MONGODB_REPLICA_SET_NAME=$KB_CLUSTER_COMP_NAME
CLIENT=`which mongosh>/dev/null&&echo mongosh||echo mongo`
CLUSTER_MONGO="$CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGODB_ADMIN_USER -p $MONGODB_ADMIN_PASSWORD --quiet --eval"

generate_endpoints() {
    # Generate the endpoints for the shard
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

wait_for_mongos() {
    # Wait for the mongos service to be ready
    while true; do
        result=$($CLUSTER_MONGO "db.adminCommand({ ping: 1 })")
        if [[ "$result" == *"ok"* ]]; then
            echo "INFO: Mongos is ready."
            break
        fi
        echo "INFO: Waiting for mongos to be ready..."
        sleep 1
    done
}


check_shard_exists() {
    # check if the shard exists in the config database
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

    # Check if the shard exists
    while ! check_shard_exists; do
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, initializing..."
        pod_endpoints=$(generate_endpoints "$MONGODB_POD_FQDN_LIST" "$KB_SERVICE_PORT")
        echo "INFO: Adding shard $MONGODB_REPLICA_SET_NAME with endpoints: $pod_endpoints"
        $CLUSTER_MONGO "sh.addShard(\"$MONGODB_REPLICA_SET_NAME/$pod_endpoints\")"
    done
    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME added."
    exit 0
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
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME is not scaling in, exiting."
        exit 0
    fi

    wait_for_mongos

    if ! check_shard_exists; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, skipping scale-in."
        exit 0
    fi

    original_balance_status=$($CLUSTER_MONGO "sh.getBalancerState()")
    if [ "$original_balance_status" = "false" ]; then
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
                dbs_to_move=$(echo "$status_json" | jq -r '.dbsToMove[]')
                note=$(echo "$status_json" | jq -r '.note')
                echo "INFO: $note"
                echo "$dbs_to_move"
                for db in $dbs_to_move; do
                    echo "INFO: Database '$db' is scheduled for movePrimary..."
                    if [ -z "$DESTINATION_SHARD" ]; then
                        DESTINATION_SHARD=$($CLUSTER_MONGO "JSON.stringify(
                            db.getSiblingDB('config').shards.find({
                                _id: { \$ne: '$MONGODB_REPLICA_SET_NAME' }
                            }).toArray()
                        )" | jq -r '.[]._id' | shuf -n 1)
                        if [ -z "$DESTINATION_SHARD" ]; then
                            echo "ERROR: No available shard found for moving primary for database '$db'."
                            exit 1
                        fi
                    fi
                    echo "INFO: Moving primary for database '$db' to shard '$DESTINATION_SHARD'..."
                    $CLUSTER_MONGO "db.adminCommand({ movePrimary: \"$db\", to: \"$DESTINATION_SHARD\" })"
                done
                continue
            else
                echo "INFO: $remaining_chunks chunks are still being migrated, waiting..."
            fi
        fi
        sleep 2
    done

    # reset balancer state
    if [ "$original_balance_status" = "false" ]; then
        $CLUSTER_MONGO "sh.stopBalancer()"
        echo "INFO: Balancer state has been reset to false."
    fi
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
    delete_or_scale_in_mongodb_shard
    exit 0
    ;;
  *)
    echo "Error: invalid option '$1'"
    exit 1
    ;;
  esac
fi