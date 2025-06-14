#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

export_pbm_env_vars

set_backup_config_env

function handle_backup_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

trap handle_backup_exit EXIT

wait_for_other_operations

sync_pbm_storage_config

echo "INFO: Starting $PBM_BACKUP_TYPE backup for MongoDB..."
backup_result=$(pbm backup --type=$PBM_BACKUP_TYPE --mongodb-uri "$PBM_MONGODB_URI" --wait -o json)
backup_name=$(echo "$backup_result" | jq -r '.name')
extras=$(buildJsonString "" "backup_name" "$backup_name")
extras=$(buildJsonString "" "backup_type" "$PBM_BACKUP_TYPE")

describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json)
backup_status=$(echo "$describe_result" | jq -r '.status')

if [ "$backup_status" != "done" ]; then
    echo "ERROR: Backup failed with status: $backup_status"
    exit 1
fi

echo "INFO: Backup description result:"
echo "$(echo $describe_result | jq)"
start_time=$(echo "$describe_result" | jq -r '.name')
end_time=$(echo "$describe_result" | jq -r '.last_write_time')
total_size=$(echo "$describe_result" | jq -r '.size')
DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"

print_pbm_logs_by_event "backup"

