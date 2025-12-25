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
  set +e
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

rs_name=$(echo "$describe_result" | jq -r '.replsets[0].name')
mappings="$MONGODB_REPLICA_SET_NAME=$rs_name"
echo "INFO: Replica set mappings: $mappings"

process_restore_start_signal

wait_for_other_operations

restore_name=$(pbm restore $backup_name --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" -o json | jq -r '.name')

wait_for_restoring

process_restore_end_signal
