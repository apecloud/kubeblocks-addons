#!/bin/bash

# shellcheck disable=SC1091
. "/scripts/mongodb-common.sh"

MONGODB_REPLICA_SET_NAME=$CLUSTER_COMPONENT_NAME
CLIENT=$(get_mongodb_client_name)
CLUSTER_MONGO="$CLIENT --host $MONGOS_INTERNAL_HOST --port $MONGOS_INTERNAL_PORT -u $MONGODB_ADMIN_USER -p $MONGODB_ADMIN_PASSWORD --quiet --eval"

wait_for_mongos() {
    # Wait for the mongos service to be ready
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
}

check_shard_exists() {
    # check if the shard exists in the config database
    local shard_exists
    shard_exists=$($CLUSTER_MONGO "db.getSiblingDB(\"config\").shards.find({ _id: \"$MONGODB_REPLICA_SET_NAME\" })" 2>/dev/null)
    if [ $? -ne 0 ]; then
        echo "ERROR: Failed to check if shard $MONGODB_REPLICA_SET_NAME exists." >&2
        exit 1
    fi
    echo "INFO: Check if shard $MONGODB_REPLICA_SET_NAME exists: $shard_exists"
    if [ -n "$shard_exists" ]; then
        return 0 # true
    else
        return 1
    fi
}

post_provision_diagnose_not_ready() {
    local phase=$1
    local retry_safe=$2

    {
        echo "postProvision diagnosis:"
        echo "action: postProvision"
        echo "phase: $phase"
        echo "component: $MONGODB_REPLICA_SET_NAME"
        echo "next-retry-safe: $retry_safe"
    } >&2
}

post_provision_run_json() {
    local expression=$1
    local serialized_expression

    case "$CLIENT" in
    mongosh | */mongosh)
        serialized_expression="EJSON.stringify(($expression))"
        ;;
    *)
        serialized_expression="JSON.stringify(($expression))"
        ;;
    esac

    POST_PROVISION_RESULT=$(timeout 5s $CLUSTER_MONGO "$serialized_expression" 2>/dev/null)
}

post_provision_json_has_numeric_ok() {
    printf '%s\n' "$1" |
        jq -e 'type == "object" and has("ok") and (.ok | type == "number")' \
            >/dev/null 2>&1
}

post_provision_json_ok_is_one() {
    printf '%s\n' "$1" |
        jq -e 'type == "object" and has("ok") and (.ok | type == "number") and .ok == 1' \
            >/dev/null 2>&1
}

post_provision_probe_mongos() {
    local command_status

    post_provision_run_json 'db.adminCommand({ ping: 1 })'
    command_status=$?
    if [ "$command_status" -ne 0 ]; then
        post_provision_diagnose_not_ready "mongos-probe-failed" "no"
        return "$command_status"
    fi

    if ! post_provision_json_has_numeric_ok "$POST_PROVISION_RESULT"; then
        post_provision_diagnose_not_ready "mongos-probe-malformed" "no"
        return 1
    fi
    if ! post_provision_json_ok_is_one "$POST_PROVISION_RESULT"; then
        post_provision_diagnose_not_ready "mongos-not-ready" "yes"
        return 1
    fi
}

post_provision_classify_presence() {
    local result=$1

    if printf '%s\n' "$result" |
        jq -e 'type == "null"' >/dev/null 2>&1; then
        POST_PROVISION_PRESENCE=absent
        return 0
    fi

    if printf '%s\n' "$result" |
        jq -e --arg name "$MONGODB_REPLICA_SET_NAME" \
            'type == "object" and has("_id") and (._id | type == "string") and ._id == $name' \
            >/dev/null 2>&1; then
        POST_PROVISION_PRESENCE=present
        return 0
    fi

    return 1
}

post_provision_probe_shard_presence() {
    local command_status

    post_provision_run_json \
        "db.getSiblingDB(\"config\").shards.findOne({ _id: \"$MONGODB_REPLICA_SET_NAME\" })"
    command_status=$?
    if [ "$command_status" -ne 0 ]; then
        post_provision_diagnose_not_ready "shard-presence-probe-failed" "no"
        return "$command_status"
    fi

    if ! post_provision_classify_presence "$POST_PROVISION_RESULT"; then
        post_provision_diagnose_not_ready "shard-presence-malformed" "no"
        return 1
    fi
}

initialize_or_scale_out_mongodb_shard() {
    local command_status
    local pod_endpoints

    post_provision_probe_mongos
    command_status=$?
    if [ "$command_status" -ne 0 ]; then
        return "$command_status"
    fi

    post_provision_probe_shard_presence
    command_status=$?
    if [ "$command_status" -ne 0 ]; then
        return "$command_status"
    fi
    if [ "$POST_PROVISION_PRESENCE" = "present" ]; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME is already present."
        return 0
    fi

    pod_endpoints=$(generate_endpoints "$MONGODB_POD_FQDN_LIST" "$KB_SERVICE_PORT")
    post_provision_run_json \
        "sh.addShard(\"$MONGODB_REPLICA_SET_NAME/$pod_endpoints\")"
    command_status=$?
    if [ "$command_status" -ne 0 ]; then
        post_provision_diagnose_not_ready "shard-add-failed" "no"
        return "$command_status"
    fi
    if ! post_provision_json_ok_is_one "$POST_PROVISION_RESULT"; then
        post_provision_diagnose_not_ready "shard-add-rejected" "no"
        return 1
    fi

    post_provision_probe_shard_presence
    command_status=$?
    if [ "$command_status" -ne 0 ]; then
        return "$command_status"
    fi
    if [ "$POST_PROVISION_PRESENCE" != "present" ]; then
        post_provision_diagnose_not_ready "shard-not-visible-after-add" "yes"
        return 1
    fi

    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME added."
}

get_remove_shard_status() {
    # Execute the removeShard command and capture its JSON output
    local result
    if [ "$CLIENT" = "mongosh" ]; then
        result=$($CLUSTER_MONGO "EJSON.stringify(db.adminCommand( { removeShard: \"$MONGODB_REPLICA_SET_NAME\" } ))")
    else
        result=$($CLUSTER_MONGO "JSON.stringify(db.adminCommand( { removeShard: \"$MONGODB_REPLICA_SET_NAME\" } ))")
    fi
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

get_remaining_jumbo_chunks() {
    local result=$1
    # Parse and log the jumboChunks count using jq
    local jumbo_chunks
    if [ "$CLIENT" = "mongosh" ]; then
        jumbo_chunks=$(echo "$result" | jq -r '.remaining.jumboChunks // 0')
    else
        jumbo_chunks=$(echo "$result" | jq -r '.remaining.jumboChunks.numberLong // 0')
    fi
    # Return the jumboChunks count as the function output
    echo "$jumbo_chunks"
}

get_remaining_chunks() {
    local result=$1
    # Parse and log the chunks count using jq
    local chunks
    if [ "$CLIENT" = "mongosh" ]; then
        chunks=$(echo "$result" | jq -r '.remaining.chunks // 0')
    else
        chunks=$(echo "$result" | jq -r '.remaining.chunks.numberLong // 0')
    fi
    # Return the chunks count as the function output
    echo "$chunks"
}

delete_or_scale_in_mongodb_shard() {
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
            remaining_jumboChunks=$(get_remaining_jumbo_chunks "$status_json")
            if [ "$remaining_jumboChunks" -gt 0 ]; then
                echo "INFO: $remaining_jumboChunks jumbo chunks remaining, please clear jumbo chunks before removing the shard."
                exit 1
            fi

            remaining_chunks=$(get_remaining_chunks "$status_json")
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
    exit $?
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
