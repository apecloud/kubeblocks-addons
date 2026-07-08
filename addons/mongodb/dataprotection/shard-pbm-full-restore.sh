#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars

set_backup_config_env

export_logs_start_time_env

trap handle_restore_exit EXIT

wait_for_other_operations

ensure_restore_coord_storage_config

extras=$(cat /dp_downward/status_extras)
backup_name=$(echo "$extras" | jq -r '.[0].backup_name // empty')
backup_type=$(echo "$extras" | jq -r '.[0].backup_type // empty')

if [ -z "$backup_type" ] || [ -z "$backup_name" ]; then
    echo "ERROR: Backup type or backup name is empty, skip restore."
    exit 1
fi

configsvr_name=$(echo "$extras" | jq -r '.[0].configsvr // empty')
shardsvr_names=$(echo "$extras" | jq -r '.[0].shardsvr // empty')
if [ -z "$configsvr_name" ] || [ -z "$shardsvr_names" ]; then
    echo "INFO: Backup extras do not contain replset mapping metadata, falling back to pbm describe-backup."
    sync_pbm_storage_config
    sync_pbm_config_from_storage
    get_describe_backup_info
    configsvr_name=$(echo "$describe_result" | jq -r '.replsets[] | select((.configsvr // false) == true or (.iscs // false) == true) | .name' | head -n 1)
    shardsvr_names=$(echo "$describe_result" | jq -r '[.replsets[] | select(((.configsvr // false) != true) and ((.iscs // false) != true)) | .name] | join(",")')
fi

echo "INFO: Config server replica set name: $configsvr_name"
echo "INFO: Shard replica set names: $shardsvr_names"
if [ -z "$configsvr_name" ] || [ -z "$shardsvr_names" ]; then
    echo "ERROR: Missing configsvr or shardsvr metadata for restore mapping."
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

echo "INFO: Starting syncer physical restore..."
restore_result=$(syncerctl_cmd restore start --backup-name "$backup_name" --type physical --replset-remapping "$mappings")
echo "INFO: Syncer restore start result: $restore_result"

wait_for_syncer_restore_completion

echo "INFO: Restore completed."
