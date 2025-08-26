#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars_for_rs

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


process_restore_start_signal

extras=$(cat /dp_downward/status_extras)
rs_name=$(echo "$extras" | jq -r '.[0].replicaset')
mappings="$MONGODB_REPLICA_SET_NAME=$rs_name"
echo "INFO: Replica set mappings: $mappings"

recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" +"%Y-%m-%dT%H:%M:%S")
echo "INFO: Recovery target time: $recovery_target_time"

echo "INFO: Starting restore..."

wait_for_other_operations

pbm restore --time="$recovery_target_time" --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" --wait

process_restore_end_signal

echo "INFO: Restore completed."
