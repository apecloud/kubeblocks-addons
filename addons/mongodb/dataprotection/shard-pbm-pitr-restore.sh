#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

set_backup_config_env

trap handle_restore_exit EXIT

prepare_restore_storage_config

recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" +"%Y-%m-%dT%H:%M:%S")
echo "INFO: Recovery target time: $recovery_target_time"

echo "INFO: Starting syncer PITR restore..."
if ! restore_result=$(syncerctl_cmd restore start --option "pitr_target=$recovery_target_time" --option type=physical --option "storage_config_token=$RESTORE_STORAGE_CONFIG_TOKEN" 2>&1); then
    echo "ERROR: Syncer restore start failed: $restore_result"
    exit 1
fi
RESTORE_REQUEST_ACCEPTED=true
echo "INFO: Syncer restore start result: $restore_result"
request_id=$(echo "$restore_result" | jq -r '.request_id // empty')

wait_for_syncer_restore_completion "$request_id"
RESTORE_COMPLETED=true

echo "INFO: Restore completed."
