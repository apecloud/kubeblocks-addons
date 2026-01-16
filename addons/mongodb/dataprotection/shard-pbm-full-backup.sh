#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

export_pbm_env_vars

set_backup_config_env

export_logs_start_time_env

trap handle_backup_exit EXIT

wait_for_other_operations

sync_pbm_storage_config

wait_for_other_operations

echo "INFO: Starting $PBM_BACKUP_TYPE backup for MongoDB..."
backup_result=$(pbm backup --type=$PBM_BACKUP_TYPE --mongodb-uri "$PBM_MONGODB_URI" --compression=$PBM_COMPRESSION --wait -o json)
backup_name=$(echo "$backup_result" | jq -r '.name')
extras=$(buildJsonString "" "backup_name" "$backup_name")
extras=$(buildJsonString $extras "backup_type" "$PBM_BACKUP_TYPE")
echo "INFO: Backup name: $backup_name"

wait_for_backup_completion

echo "INFO: Backup description result:"
echo "$(echo $describe_result | jq)"
last_write_time=$(echo "$describe_result" | jq -r '.last_write_time')
extras=$(buildJsonString $extras "last_write_time" "$last_write_time")
start_time=$(echo "$describe_result" | jq -r '.name')
end_unix_time=$(echo "$describe_result" | jq -r '.last_write_ts')
# used for pitr
end_time=$(date -u -d "@$((end_unix_time + 2))" +"%Y-%m-%dT%H:%M:%SZ")
total_size=$(echo "$describe_result" | jq -r '.size')
DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"

print_pbm_logs_by_event "backup"
