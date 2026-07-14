#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:${MOUNT_DIR}/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

set_backup_config_env

trap handle_backup_exit EXIT

prepare_pbm_operation_storage_config

echo "INFO: Starting $PBM_BACKUP_TYPE backup for MongoDB through syncer..."
backup_result=$(syncerctl_cmd backup start --option "type=$PBM_BACKUP_TYPE" --option "compression=$PBM_COMPRESSION" --option "storage_config_token=$PBM_STORAGE_CONFIG_TOKEN")
rm -f "$PBM_STORAGE_CONFIG_FILE"
PBM_STORAGE_CONFIG_FILE=""
PBM_STORAGE_CONFIG_TOKEN=""
backup_name=$(echo "$backup_result" | jq -r '.op_id // empty')
if [ -z "$backup_name" ] || [ "$backup_name" = "null" ]; then
  echo "ERROR: syncer backup start did not return op_id: $backup_result"
  exit 1
fi
echo "INFO: Backup name: $backup_name"

wait_for_syncer_backup_completion "$backup_name"

echo "INFO: Backup status result:"
echo "$(echo "$describe_result" | jq)"
save_syncer_backup_info "$describe_result"
