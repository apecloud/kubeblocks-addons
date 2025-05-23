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

initialize_or_scale_out_mongodb_shard() {
    wait_for_mongos
    # check_if_first_member
    # Check if the shard exists
    shard_exists=$($CLUSTER_MONGO "db.getSiblingDB(\"config\").shards.find({ _id: \"$MONGODB_REPLICA_SET_NAME\" });")
    if [ -n "$shard_exists" ]; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME already exists, skipping initialization."
        exit 0
    fi
    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, initializing..."
    pod_endpoints=$(generate_endpoints "$MONGODB_POD_FQDN_LIST" "$KB_SERVICE_PORT")
    echo "INFO: Adding shard $MONGODB_REPLICA_SET_NAME with endpoints: $pod_endpoints"
    $CLUSTER_MONGO "sh.addShard(\"$MONGODB_REPLICA_SET_NAME/$pod_endpoints\")"
}

scale_in_mongodb_shard() {
    # Check if the shard is scaling in
    if [[ $KB_CLUSTER_COMPONENT_IS_SCALING_IN != "true" ]]; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME is not scaling in, skipping scale-in."
        exit 0
    fi

    wait_for_mongos

    # check_if_first_member
    shard_exists=$($CLUSTER_MONGO "db.getSiblingDB(\"config\").shards.find({ _id: \"$MONGODB_REPLICA_SET_NAME\" });")
    if [ -z "$shard_exists" ]; then
        echo "INFO: Shard $MONGODB_REPLICA_SET_NAME does not exist, skipping scale-in."
        exit 0
    fi
    balance_status=$($CLUSTER_MONGO "sh.getBalancerState()")
    if [ "$balance_status" = "false" ]; then
        $CLUSTER_MONGO "sh.startBalancer()"
    fi

    echo "INFO: Shard $MONGODB_REPLICA_SET_NAME exists, scaling in..."
    # Remove the shard and wait until the state is 'completed'
    while true; do
      result=$($CLUSTER_MONGO "db.adminCommand( { removeShard: \"$MONGODB_REPLICA_SET_NAME\" } )")
      echo "$result"
      # Extract the state field from the output
      state=$(echo "$result" | grep -o "state': '[^']*" | cut -d"'" -f3)
      echo "INFO: Shard $MONGODB_REPLICA_SET_NAME state is $state"
      if [ "$state" = "completed" ]; then
        break
      fi
      sleep 2
    done
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
    scale_in_mongodb_shard
    exit 0
    ;;
  *)
    echo "Error: invalid option '$1'"
    exit 1
    ;;
  esac
fi