#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars

set_backup_config_env

trap handle_restore_exit EXIT

wait_for_other_operations

prepare_restore_storage_config

extras=$(cat /dp_downward/status_extras)
configsvr_name=$(echo "$extras" | jq -r '.[0].configsvr // empty')
echo "INFO: Config server replica set name: $configsvr_name"
shardsvr_names=$(echo "$extras" | jq -r '.[0].shardsvr // empty')
echo "INFO: Shard replica set names: $shardsvr_names"
if [ -z "$configsvr_name" ] || [ -z "$shardsvr_names" ]; then
    echo "ERROR: Missing configsvr or shardsvr metadata for PITR restore mapping."
    exit 1
fi

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
    if [ $shardsvr_count -gt 1 ]; then
        shard_name="$CLUSTER_NAME-${new_shardsvr_array[i]%%@*}"
    else
        shard_name="${new_shardsvr_array[i]%%,*}"
    fi
    echo "INFO: Mapping shard ${shardsvr_array[i]} to $shard_name"
    if [ $i -eq 0 ]; then
        mappings="${shard_name}=${shardsvr_array[i]}"
    else
        mappings="$mappings,${shard_name}=${shardsvr_array[i]}"
    fi
done

echo "INFO: Mapping config server $configsvr_name to $CFG_SERVER_REPLICA_SET_NAME"
mappings="$mappings,$CFG_SERVER_REPLICA_SET_NAME=$configsvr_name"
echo "INFO: Shard mappings: $mappings"

recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" +"%Y-%m-%dT%H:%M:%S")
echo "INFO: Recovery target time: $recovery_target_time"

echo "INFO: Starting syncer PITR restore..."
if ! restore_result=$(syncerctl_cmd restore start --pitr-target "$recovery_target_time" --type physical --replset-remapping "$mappings" --storage-config-file "$RESTORE_STORAGE_CONFIG_FILE" 2>&1); then
    rm -f "$RESTORE_STORAGE_CONFIG_FILE"
    echo "ERROR: Syncer restore start failed: $restore_result"
    exit 1
fi
rm -f "$RESTORE_STORAGE_CONFIG_FILE"
echo "INFO: Syncer restore start result: $restore_result"
request_id=$(echo "$restore_result" | jq -r '.request_id // empty')

wait_for_syncer_restore_completion "$request_id"

echo "INFO: Restore completed."
