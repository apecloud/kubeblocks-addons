#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:${MOUNT_DIR}/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

export_pbm_env_vars_for_rs

set_backup_config_env

trap handle_backup_exit EXIT

wait_for_other_operations

configure_syncer_backup

wait_for_other_operations

echo "INFO: Starting $PBM_BACKUP_TYPE backup for MongoDB through syncer..."
backup_result=$(syncerctl_cmd backup start --type="$PBM_BACKUP_TYPE" --compression="$PBM_COMPRESSION")
backup_name=$(echo "$backup_result" | jq -r '.op_id // empty')
if [ -z "$backup_name" ] || [ "$backup_name" = "null" ]; then
  echo "ERROR: syncer backup start did not return op_id: $backup_result"
  exit 1
fi
extras=$(buildJsonString "" "backup_name" "$backup_name")
extras=$(buildJsonString $extras "backup_type" "$PBM_BACKUP_TYPE")
echo "INFO: Backup name: $backup_name"

wait_for_syncer_backup_completion "$backup_name"

echo "INFO: Backup status result:"
echo "$(echo "$describe_result" | jq)"

rs_name=$(echo "$describe_result" | jq -r '[.replsets[]? | .name] | .[0] // empty')
if [ -z "$rs_name" ] || [ "$rs_name" = "null" ]; then
  rs_name="$MONGODB_REPLICA_SET_NAME"
fi
extras=$(buildJsonString $extras "replicaset" "$rs_name")

last_write_unix=$(echo "$describe_result" | jq -r '.last_write_ts.t // .last_write_ts.T // .last_write_ts // empty')
if [[ "$last_write_unix" =~ ^[0-9]+$ ]]; then
  last_write_time=$(date -u -d "@${last_write_unix}" +"%Y-%m-%dT%H:%M:%SZ")
  end_time=$(date -u -d "@$((last_write_unix + 2))" +"%Y-%m-%dT%H:%M:%SZ")
else
  last_write_time=""
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
extras=$(buildJsonString $extras "last_write_time" "$last_write_time")

start_unix=$(echo "$describe_result" | jq -r '.start_ts // empty')
if [[ "$start_unix" =~ ^[0-9]+$ ]]; then
  start_time=$(date -u -d "@${start_unix}" +"%Y-%m-%dT%H:%M:%SZ")
else
  start_time="$backup_name"
fi
total_size=$(echo "$describe_result" | jq -r '.size // 0')
DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"
