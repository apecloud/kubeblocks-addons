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

rs_name=$(echo "$describe_result" | jq -r '.replsets[0].name')
mappings="$MONGODB_REPLICA_SET_NAME=$rs_name"
echo "INFO: Replica set mappings: $mappings"

process_restore_start_signal

wait_for_other_operations

pbm restore $backup_name --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" --wait

process_restore_end_signal
