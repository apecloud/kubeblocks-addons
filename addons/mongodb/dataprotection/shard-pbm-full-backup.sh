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

# The ActionSet job renders PBM storage config from datasafed, so seed it
# before delegating backup control to syncer.
wait_for_other_operations
sync_pbm_storage_config
wait_for_other_operations

echo "INFO: Starting $PBM_BACKUP_TYPE backup via syncerctl..."
backup_result=$(syncerctl_exec backup start --type "$PBM_BACKUP_TYPE" --compression "$PBM_COMPRESSION")
backup_name=$(echo "$backup_result" | jq -r '.op_id')
extras=$(buildJsonString "" "backup_name" "$backup_name")
extras=$(buildJsonString $extras "backup_type" "$PBM_BACKUP_TYPE")
echo "INFO: Backup name: $backup_name"

# Poll backup status via syncerctl
echo "INFO: Waiting for backup completion..."
describe_result=""
retry_interval=5
attempt=1
max_retries=60
set +e
while true; do
  describe_result=$(syncerctl_exec backup status --op-id "$backup_name" 2>&1)
  if [ $? -eq 0 ] && [ -n "$describe_result" ]; then
    backup_status=$(echo "$describe_result" | jq -r '.status')
    if [ "$backup_status" = "starting" ] || [ "$backup_status" = "running" ]; then
      echo "INFO: Backup status is $backup_status, retrying in ${retry_interval}s..."
    elif [ "$backup_status" = "done" ]; then
      echo "INFO: Backup status is done."
      break
    elif [ "$backup_status" = "error" ] || [ "$backup_status" = "canceled" ]; then
      echo "ERROR: Backup failed with status: $backup_status"
      exit 1
    else
      echo "INFO: Backup status is $backup_status, retrying in ${retry_interval}s..."
      attempt=$((attempt+1))
    fi
  else
    echo "INFO: Failed to get backup status, retrying in ${retry_interval}s..."
    attempt=$((attempt+1))
  fi
  sleep $retry_interval
  if [ $attempt -gt $max_retries ]; then
    echo "ERROR: Failed to get backup status after $max_retries attempts"
    exit 1
  fi
done
set -e

echo "INFO: Backup description result:"
echo "$describe_result" | jq
last_write_time=$(echo "$describe_result" | jq -r '.last_transition_ts // .start_ts // empty')
extras=$(buildJsonString $extras "last_write_time" "$last_write_time")
start_ts=$(echo "$describe_result" | jq -r '.start_ts // empty')
if [ -n "$start_ts" ]; then
  start_time=$(date -u -d "@$start_ts" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u -r "$start_ts" +"%Y-%m-%dT%H:%M:%SZ")
else
  start_time=$(echo "$describe_result" | jq -r '.op_id')
fi
end_unix_time=$(echo "$describe_result" | jq -r '.last_transition_ts // empty')
if [ -n "$end_unix_time" ]; then
  end_time=$(date -u -d "@$((end_unix_time + 2))" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null || date -u +"%Y-%m-%dT%H:%M:%SZ")
else
  end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
fi
total_size=$(echo "$describe_result" | jq -r '.size // "0"')
DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"

print_pbm_logs_by_event "backup"
