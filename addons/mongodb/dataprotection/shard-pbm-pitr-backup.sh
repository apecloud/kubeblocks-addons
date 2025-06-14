#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

function enable_pitr() {
  local current_pitr_conf=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.pitr')
  local current_pitr_enabled=$(current_pitr_conf | jq -r '.enabled')
  local current_oplog_span_min=$(current_pitr_conf | jq -r '.oplogSpanMin')
  local current_pitr_compression=$(current_pitr_conf | jq -r '.compression')

  echo "INFO: Starting continuous backup for MongoDB..."
  if [ "$current_pitr_enabled" != "true" ] || [ "$current_oplog_span_min" != "$PBM_OPLOG_SPAN_MIN_MINUTES" ] || [ "$current_pitr_compression" != "$PBM_COMPRESSION" ]; then
    wait_for_other_operations

    cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin > /dev/null
pitr:
  enabled: true
  oplogSpanMin: $PBM_OPLOG_SPAN_MIN_MINUTES
  compression: $PBM_COMPRESSION
EOF
  fi
  echo "INFO: Continuous backup enabled."
}

function disable_pitr() {
  pbm config --set pitr.enabled=false --mongodb-uri "$PBM_MONGODB_URI"
  echo "INFO: Continuous backup disabled."
}

function export_logs_start_time_env() {
  local logs_start_time=$(date +"%Y-%m-%dT%H:%M:%SZ")
  export PBM_LOGS_START_TIME="${logs_start_time}"
}

function upload_continuous_backup_info() {
  local pitr_chunks_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.backups.pitrChunks')
  echo "INFO: Continuous backup result:"
  echo "$(echo $pitr_chunks_result | jq)"
  local filtered_sorted_chunks=$(echo "$pitr_chunks_result" | jq -r '.pitrChunks' | jq 'map(select(.noBaseSnapshot != true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ]; then
    echo "INFO: No oplog found."
    return
  fi
  local last_chunk=$(echo "$filtered_sorted_chunks" | jq -r '.[-1].range')
  local start_unix_time=$(echo "$last_chunk" | jq -r '.start')
  local end_unix_time=$(echo "$last_chunk" | jq -r '.end')
  local start_time=$(date -u -d "@${start_unix_time}" +"%Y-%m-%dT%H:%M:%SZ")
  local end_time=$(date -u -d "@${end_unix_time}" +"%Y-%m-%dT%H:%M:%SZ")
  local total_size=$(echo "$pitr_chunks_result" | jq -r '.size')

  local backup_type="continuous"
  local extras=$(buildJsonString "" "backup_type" "$backup_type")
  DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"
}

function sync_pbm_config_from_storage() {
  pbm config --force-resync --wait --mongodb-uri "$PBM_MONGODB_URI"
  print_pbm_logs_by_event "resync"
}

function purge_pitr_chunks() {
  current_hour=$(date -u +"%H")
  if [ "$current_hour" != "$PBM_PURGE_HOUR" ]; then
    return
  fi
  
  wait_for_other_operations

  sync_pbm_config_from_storage

  local pitr_chunks_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.backups.pitrChunks')
  local filtered_sorted_chunks=$(echo "$pitr_chunks_result" | jq -r '.pitrChunks' | jq -e 'map(select(.noBaseSnapshot == true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ] || [ "$filtered_sorted_chunks" = "[]" ]; then
    return
  fi
  echo "INFO: No base snapshot chunks:"
  echo "$(echo $filtered_sorted_chunks | jq)"
  local first_chunk_end=$(echo "$filtered_sorted_chunks" | jq -r '.[0].range.end')
  purge_time=$(date -u -d "@${first_chunk_end}" +"%Y-%m-%dT%H:%M:%S")
  pbm cleanup --older-than $purge_time --mongodb-uri "$PBM_MONGODB_URI" --wait --yes
  echo "INFO: No base snapshot chunks cleaned up."
}

function handle_pitr_exit() {

  print_pbm_tail_logs

  disable_pitr

  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}


export_pbm_env_vars

set_backup_config_env

export_logs_start_time_env

trap handle_pitr_exit EXIT

while true; do
  wait_for_other_operations

  sync_pbm_storage_config

  enable_pitr

  upload_continuous_backup_info

  purge_pitr_chunks

  print_pbm_logs_by_event "pitr"

  export_logs_start_time_env

  sleep 5
done