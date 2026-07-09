#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars_for_rs

set_backup_config_env

export_logs_start_time_env

trap handle_restore_exit EXIT

wait_for_other_operations

ensure_restore_coord_storage_config

extras=$(cat /dp_downward/status_extras)
rs_name=$(echo "$extras" | jq -r '.[0].replicaset // empty')
if [ -z "$rs_name" ] || [ "$rs_name" = "null" ]; then
    echo "ERROR: Missing source replica set metadata for PITR restore mapping."
    exit 1
fi

mappings="$MONGODB_REPLICA_SET_NAME=$rs_name"
echo "INFO: Replica set mappings: $mappings"

recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" +"%Y-%m-%dT%H:%M:%S")
echo "INFO: Recovery target time: $recovery_target_time"

echo "INFO: Starting syncer PITR restore..."
if ! restore_result=$(syncerctl_cmd restore start --pitr-target "$recovery_target_time" --type physical --replset-remapping "$mappings" 2>&1); then
    echo "ERROR: Syncer restore start failed: $restore_result"
    exit 1
fi
echo "INFO: Syncer restore start result: $restore_result"

wait_for_syncer_restore_completion

echo "INFO: Restore completed."
