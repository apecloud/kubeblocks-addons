#!/bin/bash

# When doing point-in-time recovery for deployments with sharded collections,
# PBM only writes data to existing ones and doesn't support creating new collections.
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

function enable_pitr() {
  # Use syncerctl to enable PITR via syncer API
  syncerctl_exec pitr enable --oplog-span-min "$PBM_OPLOG_SPAN_MIN_MINUTES" --compression "$PBM_COMPRESSION"
  echo "INFO: PITR enabled via syncerctl."
}

function disable_pitr() {
  echo "INFO: Disabling PITR via syncerctl..."
  syncerctl_exec pitr disable
  echo "INFO: PITR disabled."
}

function upload_continuous_backup_info() {
  # Use syncerctl pitr status to get PITR info
  local pitr_result=$(syncerctl_exec pitr status 2>/dev/null)
  if [ -z "$pitr_result" ]; then
    echo "INFO: No PITR status available."
    return
  fi
  echo "INFO: PITR status:"
  echo "$pitr_result" | jq

  local backup_type="continuous"
  local extras=$(buildJsonString "" "backup_type" "$backup_type")
  extras=$(buildJsonString $extras "replicaset" "$MONGODB_REPLICA_SET_NAME")

  # PITR chunk time range - use current time as end
  local end_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  local total_size=$(echo "$pitr_result" | jq -r '.oplog_span_min // "0"')
  DP_save_backup_status_info "$total_size" "" "$end_time" "" "{$extras}"
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
  echo "INFO: Purging PBM chunks..."
  wait_for_other_operations "backup"
  pbm config --force-resync --mongodb-uri "$PBM_MONGODB_URI"
  wait_for_other_operations "backup"

  pitr_chunks_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.backups.pitrChunks')
  pitr_chunks_arr=$(echo "$pitr_chunks_result" | jq -r '.pitrChunks')
  if [ -z "$pitr_chunks_arr" ] || [ "$pitr_chunks_arr" = "null" ] || [ "$pitr_chunks_arr" = "[]" ]; then
    echo "INFO: No no base snapshot chunks found."
    return
  fi
  filtered_sorted_chunks=$(echo "$pitr_chunks_arr" | jq -e 'map(select(.noBaseSnapshot == true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ] || [ "$filtered_sorted_chunks" = "null" ] || [ "$filtered_sorted_chunks" = "[]" ]; then
    echo "INFO: No no base snapshot chunks."
    return
  fi
  first_chunk_end=$(echo "$filtered_sorted_chunks" | jq -r '.[0].range.end')
  purge_time=$(date -u -d "@${first_chunk_end}" +"%Y-%m-%dT%H:%M:%S")
  pbm cleanup --older-than "$purge_time" --mongodb-uri "$PBM_MONGODB_URI" --wait --yes
  echo "INFO: PBM chunks purged."
}

export_pbm_env_vars_for_rs

set_backup_config_env

export_logs_start_time_env

trap handle_pitr_exit EXIT

sync_pbm_storage_config
sync_pbm_config_from_storage

while true; do
  wait_for_other_operations "backup"

  sync_pbm_storage_config 2>/dev/null || true

  enable_pitr

  purge_pitr_chunks

  upload_continuous_backup_info

  print_pbm_logs_by_event "pitr"

  export_logs_start_time_env

  sleep 30
done
