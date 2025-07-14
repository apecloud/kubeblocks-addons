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
configsvr_name=$(echo "$extras" | jq -r '.[0].configsvr')
echo "INFO: Config server replica set name: $configsvr_name"
shardsvr_names=$(echo "$extras" | jq -r '.[0].shardsvr')
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
        shard_name="${new_shardsvr_array[i]%%,*}"
        shard_name="${shard_name%-*}"
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

process_restore_start_signal

recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" +"%Y-%m-%dT%H:%M:%S")
echo "INFO: Recovery target time: $recovery_target_time"


echo "INFO: Starting restore..."

wait_for_other_operations

pbm restore --time="$recovery_target_time" --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" --wait

process_restore_end_signal

echo "INFO: Restore completed."
