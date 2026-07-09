#!/bin/bash

# For PITR with PBM physical backups, create a fresh base backup whenever new collections must be included by restore.
# Ref: https://docs.percona.com/percona-backup-mongodb/usage/pitr-physical.html#post-restore-steps
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:${MOUNT_DIR}/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

function enable_pitr() {
  local current_pitr_conf
  current_pitr_conf=$(syncerctl_cmd pitr status)
  local current_pitr_enabled
  local current_oplog_span_min
  local current_pitr_compression
  current_pitr_enabled=$(echo "$current_pitr_conf" | jq -r '.enabled // false')
  current_oplog_span_min=$(echo "$current_pitr_conf" | jq -r '.oplog_span_min // empty')
  current_pitr_compression=$(echo "$current_pitr_conf" | jq -r '.compression // empty')

  if [ "$current_pitr_enabled" != "true" ] || [ "$current_oplog_span_min" != "$PBM_OPLOG_SPAN_MIN_MINUTES" ] || [ "$current_pitr_compression" != "$PBM_COMPRESSION" ]; then
    echo "INFO: PITR config is not equal to the desired config, updating through syncer..."
    wait_for_other_operations "backup"
    syncerctl_cmd pitr enable --oplog-span-min "$PBM_OPLOG_SPAN_MIN_MINUTES" --compression "$PBM_COMPRESSION"
    echo "INFO: PITR config updated."
  fi
}

function disable_pitr() {
  echo "INFO: Disabling PITR through syncer..."
  syncerctl_cmd pitr disable
  echo "INFO: PITR disabled."
}

function upload_continuous_backup_info() {
  local status_result
  status_result=$(syncerctl_cmd pitr chunks)
  echo "INFO: Uploading continuous backup info..."
  echo "INFO: Continuous backup result:"
  echo "$(echo "$status_result" | jq)"
  local pitr_chunks_arr
  pitr_chunks_arr=$(echo "$status_result" | jq -r '.pitrChunks')
  if [ -z "$pitr_chunks_arr" ] || [ "$pitr_chunks_arr" = "null" ] || [ "$pitr_chunks_arr" = "[]" ]; then
    echo "INFO: No oplog found."
    return
  fi
  local filtered_sorted_chunks
  filtered_sorted_chunks=$(echo "$pitr_chunks_arr" | jq 'map(select(.noBaseSnapshot != true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ] || [ "$filtered_sorted_chunks" = "null" ] || [ "$filtered_sorted_chunks" = "[]" ]; then
    echo "INFO: No oplog found."
    return
  fi
  local last_chunk
  last_chunk=$(echo "$filtered_sorted_chunks" | jq -r '.[-1].range')
  local start_unix_time
  local end_unix_time
  start_unix_time=$(echo "$last_chunk" | jq -r '.start')
  end_unix_time=$(echo "$last_chunk" | jq -r '.end')
  local start_time
  local end_time
  start_time=$(date -u -d "@${start_unix_time}" +"%Y-%m-%dT%H:%M:%SZ")
  end_time=$(date -u -d "@${end_unix_time}" +"%Y-%m-%dT%H:%M:%SZ")
  local total_size
  total_size=$(echo "$status_result" | jq -r '.size // 0')

  local backup_type="continuous"
  local extras
  extras=$(buildJsonString "" "backup_type" "$backup_type")
  extras=$(buildJsonString $extras "replicaset" "$MONGODB_REPLICA_SET_NAME")

  DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"
  echo "INFO: Continuous backup info uploaded."
}

function purge_pitr_chunks() {
  current_time=$(date +%s)

  if [ -z "$last_global_purge_time" ]; then
    last_global_purge_time=0
  fi

  time_diff=$((current_time - last_global_purge_time))

  if [ $time_diff -lt $(( ${PBM_PURGE_INTERVAL_SECONDS:-86400} )) ]; then
    return
  fi

  last_global_purge_time=$current_time

  echo "INFO: Purging PBM chunks through syncer..."
  wait_for_other_operations "backup"

  local status_result
  local pitr_chunks_arr
  status_result=$(syncerctl_cmd pitr chunks)
  pitr_chunks_arr=$(echo "$status_result" | jq -r '.pitrChunks')
  if [ -z "$pitr_chunks_arr" ] || [ "$pitr_chunks_arr" = "null" ] || [ "$pitr_chunks_arr" = "[]" ]; then
    echo "INFO: No no-base-snapshot chunks found."
    return
  fi
  local filtered_sorted_chunks
  filtered_sorted_chunks=$(echo "$pitr_chunks_arr" | jq -e 'map(select(.noBaseSnapshot == true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ] || [ "$filtered_sorted_chunks" = "null" ] || [ "$filtered_sorted_chunks" = "[]" ]; then
    echo "INFO: No no-base-snapshot chunks."
    return
  fi
  echo "INFO: No-base-snapshot chunks:"
  echo "$(echo "$filtered_sorted_chunks" | jq)"
  local first_chunk_end
  first_chunk_end=$(echo "$filtered_sorted_chunks" | jq -r '.[0].range.end')
  purge_time=$(date -u -d "@${first_chunk_end}" +"%Y-%m-%dT%H:%M:%S")
  syncerctl_cmd pitr cleanup --older-than "$purge_time"
  echo "INFO: No-base-snapshot chunks cleanup requested."
}

export_pbm_env_vars_for_rs

set_backup_config_env

export_logs_start_time_env

trap handle_pitr_exit EXIT

# Apply storage once. Re-applying the storage file in the loop clears PBM PITR settings
# and restarts slicing before chunks can mature.
configure_syncer_backup

while true; do
  wait_for_other_operations "backup"

  enable_pitr

  purge_pitr_chunks

  upload_continuous_backup_info

  print_pbm_logs_by_event "pitr"

  export_logs_start_time_env

  sleep 30
done
