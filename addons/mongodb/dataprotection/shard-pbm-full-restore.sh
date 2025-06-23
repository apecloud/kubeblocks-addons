#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars

set_backup_config_env

export_logs_start_time_env

function handle_restore_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    exit 1
  fi
}

trap handle_restore_exit EXIT

wait_for_other_operations

sync_pbm_storage_config

sync_pbm_config_from_storage

extras=$(cat /dp_downward/status_extras)
backup_name=$(echo "$extras" | jq -r '.[0].backup_name')
backup_type=$(echo "$extras" | jq -r '.[0].backup_type')

if [ -z "$backup_type" ] || [ -z "$backup_name" ]; then
    echo "ERROR: Backup type or backup name is empty, skip restore."
    exit 1
fi

MAX_RETRIES=360
RETRY_INTERVAL=2
attempt=1
describe_result=""
set +e
while [ $attempt -le $MAX_RETRIES ]; do
    describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json 2>&1)
    if [ $? -eq 0 ] && [ -n "$describe_result" ]; then
        break
    elif echo "$describe_result" | grep -q "not found"; then
        echo "INFO: Attempt $attempt: Failed to get backup metadata, retrying in ${RETRY_INTERVAL}s..."
        sleep $RETRY_INTERVAL
        ((attempt++))
        continue
    else
        echo "ERROR: Failed to get backup metadata: $describe_result"
    fi
done
set -e

if [ -z "$describe_result" ]; then
    echo "ERROR: Failed to get backup metadata after $MAX_RETRIES attempts"
    exit 1
fi

configsvr_name=$(echo "$describe_result" | jq -r '.replsets[] | select(.configsvr == true) | .name')
echo "INFO: Config server replica set name: $configsvr_name"
shardsvr_names=$(echo "$describe_result" | jq -r '[.replsets[] | select(.configsvr != true) | .name] | join(",")')
echo "INFO: Shard replica set names: $shardsvr_names"
mappings=""
IFS="," read -r -a shardsvr_array <<< "$shardsvr_names"
shardsvr_count=${#shardsvr_array[@]}
if [ $shardsvr_count -lt 1 ]; then
    echo "ERROR: No shard replica set found in the backup."
    exit 1
fi
IFS="." read -r -a new_shardsvr_array <<< "$MONGODB_SHARD_REPLICA_SET_NAME_LIST"
new_shardsvr_count=${#new_shardsvr_array[@]}
if [ $new_shardsvr_count -ne $shardsvr_count ]; then
    echo "ERROR: The number of shard replica sets is not equal to the number of new shard replica sets."
    exit 1
fi
for i in "${!shardsvr_array[@]}"; do
    # Get the part before "@" in new_shardsvr_array
    if [ $shardsvr_count -gt 1 ]; then
        shard_name="$KB_CLUSTER_NAME-${new_shardsvr_array[i]%%@*}"
    else
        shard_name="${new_shardsvr_array[i]%-*}"
    fi
    echo "INFO: Mapping shard ${shardsvr_array[i]} to $shard_name"
    if [ $i -eq 0 ]; then
        mappings="${shard_name}=${shardsvr_array[i]}"
    else
        mappings="$mappings,${shard_name}=${shardsvr_array[i]}"
    fi
done
# If the config server name is not empty, add it to the mappings
echo "INFO: Mapping config server $configsvr_name to $CFG_SERVER_REPLICA_SET_NAME"
mappings="$mappings,$CFG_SERVER_REPLICA_SET_NAME=$configsvr_name"
echo "INFO: Shard mappings: $mappings"

# check if restore is running in case of fallback
# if pbm status --mongodb-uri "$PBM_MONGODB_URI" | grep -q "restore"; then
#     echo "ERROR: Restore is already running, cannot start a new restore."
#     exit 1
# fi

create_restore_signal() {
    phase=$1
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $dp_cm_name
  namespace: $dp_cm_namespace
  labels:
    app.kubernetes.io/instance: $KB_CLUSTER_NAME
    apps.kubeblocks.io/restore-mongodb-shard: $phase
EOF
}

if [ "$backup_type" = "physical" ]; then
    echo "INFO: Waiting for prepare restore start signal..."
    dp_cm_name="$KB_CLUSTER_NAME-restore-signal"
    dp_cm_namespace="$KB_NAMESPACE"
    while true; do
        set +e
        kubectl_get_result=$(kubectl get configmap $dp_cm_name -n $dp_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        set -e
        # Wait for the restore signal ConfigMap to be created or updated
        if [[ "$kubectl_get_exit_code" -ne 0 ]]; then
            if [[ "$kubectl_get_result" == *"not found"* ]]; then
                create_restore_signal "start"
            fi
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            if [[ "$annotation_value" == "start" ]]; then
                break
            elif [[ "$annotation_value" == "end" ]]; then
                echo "INFO: Restore completed, exiting."
                exit 0
            else
                echo "INFO: Restore start signal is $annotation_value, updating..."
                create_restore_signal "start"
            fi
        fi
        sleep 1
    done
    sleep 5
    echo "INFO: Prepare restore start signal completed."
fi

pbm restore $backup_name --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" --wait

print_pbm_logs_by_event "restore"

if [ "$backup_type" = "physical" ]; then
    echo "INFO: Waiting for prepare restore end signal..."
    dp_cm_name="$KB_CLUSTER_NAME-restore-signal"
    dp_cm_namespace="$KB_NAMESPACE"
    while true; do
        set +e
        kubectl_get_result=$(kubectl get configmap $dp_cm_name -n $dp_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        set -e
        # Wait for the restore signal ConfigMap to be created or updated
        if [[ "$kubectl_get_exit_code" -ne 0 ]]; then
            if [[ "$kubectl_get_result" == *"not found"* ]]; then
                create_restore_signal "end"
            fi
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            if [[ "$annotation_value" == "end" ]]; then
                break
            else
                echo "INFO: Restore end signal is $annotation_value, updating..."
                create_restore_signal "end"
            fi
        fi
        sleep 1
    done
    echo "INFO: Prepare restore end signal completed."
fi
