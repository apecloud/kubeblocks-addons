#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars_for_rs

set_backup_config_env

export_logs_start_time_env

trap handle_restore_exit EXIT

# The ActionSet job renders PBM storage config from datasafed, and restore
# targets must force PBM to resync metadata before syncer starts the restore.
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

# Get backup info for replset name mapping via syncerctl.
describe_result=$(syncerctl_exec backup status --op-id "$backup_name")
rs_name=$(echo "$describe_result" | jq -r '.replsets[0].name')
mappings="$MONGODB_REPLICA_SET_NAME=$rs_name"
echo "INFO: Replica set mappings: $mappings"

process_restore_start_signal

# Trigger restore via syncerctl instead of direct pbm restore
echo "INFO: Starting restore via syncerctl..."
restore_result=$(syncerctl_exec restore start --backup-name "$backup_name" --replset-remapping "$mappings")
restore_name=$(echo "$restore_result" | jq -r '.op_id')

# Poll restore status via syncerctl
echo "INFO: Waiting for restore completion..."
retry_interval=5
attempt=0
max_retries=60
set +e
while true; do
  restore_status_result=$(syncerctl_exec restore status --op-id "$restore_name" 2>&1)
  if [ $? -eq 0 ] && [ -n "$restore_status_result" ]; then
    status=$(echo "$restore_status_result" | jq -r '.status')
    echo "INFO: Restore $restore_name status: $status"
    if [ "$status" = "done" ]; then
      break
    elif [ "$status" = "error" ]; then
      echo "ERROR: Restore failed"
      set -e
      exit 1
    fi
  else
    echo "INFO: Failed to get restore status, retrying..."
    attempt=$((attempt+1))
  fi
  sleep $retry_interval
  if [ $attempt -gt $max_retries ]; then
    echo "ERROR: Restore status polling exceeded $max_retries retries"
    set -e
    exit 1
  fi
done
set -e

process_restore_end_signal

echo "INFO: Restore completed."
