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

get_describe_backup_info

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
# If the config server name is not empty, add it to the mappings
echo "INFO: Mapping config server $configsvr_name to $CFG_SERVER_REPLICA_SET_NAME"
mappings="$mappings,$CFG_SERVER_REPLICA_SET_NAME=$configsvr_name"
echo "INFO: Shard mappings: $mappings"

process_restore_start_signal

wait_for_other_operations

restore_name=$(pbm restore $backup_name --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" -o json | jq -r '.name')

wait_for_restoring

process_restore_end_signal
