#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

set_backup_config_env

trap handle_restore_exit EXIT

prepare_restore_storage_config

extras=$(cat /dp_downward/status_extras)
backup_name=$(echo "$extras" | jq -r '.[0].backup_name // empty')
backup_type=$(echo "$extras" | jq -r '.[0].backup_type // empty')

if [ -z "$backup_type" ] || [ -z "$backup_name" ]; then
    echo "ERROR: Backup type or backup name is empty, skip restore."
    exit 1
fi

echo "INFO: Starting syncer physical restore..."
if ! restore_result=$(syncerctl_cmd restore start --backup-name "$backup_name" --type physical --storage-config-token "$RESTORE_STORAGE_CONFIG_TOKEN" 2>&1); then
    echo "ERROR: Syncer restore start failed: $restore_result"
    exit 1
fi
RESTORE_REQUEST_ACCEPTED=true
echo "INFO: Syncer restore start result: $restore_result"
request_id=$(echo "$restore_result" | jq -r '.request_id // empty')

wait_for_syncer_restore_completion "$request_id"
RESTORE_COMPLETED=true

echo "INFO: Restore completed."
