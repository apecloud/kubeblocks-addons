#!/bin/bash

# When doing point-in-time recovery for deployments with sharded collections, PBM only writes data to existing ones and doesn’t support creating new collections.
# Therefore, whenever you create a new sharded collection, make a new backup for it to be included there. Ref: https://docs.percona.com/percona-backup-mongodb/usage/pitr-physical.html#post-restore-steps
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

function enable_pitr() {
  local current_pitr_conf=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.pitr')
  local current_pitr_enabled=$(echo $current_pitr_conf | jq -r '.enabled')
  local current_oplog_span_min=$(echo $current_pitr_conf | jq -r '.oplogSpanMin')
  local current_pitr_compression=$(echo $current_pitr_conf | jq -r '.compression')

  if [ "$current_pitr_enabled" != "true" ] || [ "$current_oplog_span_min" != "$PBM_OPLOG_SPAN_MIN_MINUTES" ] || [ "$current_pitr_compression" != "$PBM_COMPRESSION" ]; then
    echo "INFO: Pitr config is not equal to the current config, updating..."
    wait_for_other_operations "backup"

    pbm config --mongodb-uri "$PBM_MONGODB_URI" --set pitr.enabled=true --set pitr.oplogSpanMin=$PBM_OPLOG_SPAN_MIN_MINUTES --set pitr.compression=$PBM_COMPRESSION
    echo "INFO: Pitr config updated."
  fi
}

function disable_pitr() {
  echo "INFO: Disabling Pitr..."
  pbm config --set pitr.enabled=false --mongodb-uri "$PBM_MONGODB_URI"
  echo "INFO: Pitr disabled."
}

function upload_continuous_backup_info() {
  local status_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json)
  echo "INFO: Uploading continuous backup info..."
  local pitr_chunks_result=$(echo "$status_result" | jq -r '.backups.pitrChunks')
  echo "INFO: Continuous backup result:"
  echo "$(echo $pitr_chunks_result | jq)"
  local pitr_chunks_arr=$(echo "$pitr_chunks_result" | jq -r '.pitrChunks')
  if [ -z "$pitr_chunks_arr" ] || [ "$pitr_chunks_arr" = "null" ] || [ "$pitr_chunks_arr" = "[]" ]; then
    echo "INFO: No oplog found."
    return
  fi
  local filtered_sorted_chunks=$(echo "$pitr_chunks_arr" | jq 'map(select(.noBaseSnapshot != true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ] || [ "$filtered_sorted_chunks" = "null" ] || [ "$filtered_sorted_chunks" = "[]" ]; then
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

  local pitr_nodes=$(echo "$status_result" | jq -r '.pitr.nodes?[]?')
  local shardsvr=""
  local configsvr=""
  while IFS= read -r node; do
    if [[ -n "$node" ]]; then
      # Extract the text before the first "/"
      local node_name=${node%%/*}
      if [[ "$node" == *"config"* ]]; then
        configsvr="$node_name"
      else
        if [ -z "$shardsvr" ]; then
          shardsvr="$node_name"
        else
          shardsvr="$shardsvr,$node_name"
        fi
      fi
    fi
  done <<< "$pitr_nodes"
  if [ -z "$shardsvr" ]; then
    shardsvr=$(echo "$status_result" | jq -r '[.cluster[].rs | select(contains("config-server") | not)] | join(",")')
  fi
  if [ -z "$configsvr" ]; then
    configsvr=$(echo "$status_result" | jq -r '[.cluster[].rs | select(contains("config-server"))] | join(",")')
  fi
  extras=$(buildJsonString $extras "shardsvr" "$shardsvr")
  extras=$(buildJsonString $extras "configsvr" "$configsvr")
  DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"
  echo "INFO: Continuous backup info uploaded."
}

function purge_pitr_chunks() {
  current_time=$(date +%s)
  
  # Initialize last_global_purge_time if not set
  if [ -z "$last_global_purge_time" ]; then
    last_global_purge_time=0
  fi
  
  time_diff=$((current_time - last_global_purge_time))
  
  if [ $time_diff -lt $(( ${PBM_PURGE_INTERVAL_SECONDS:-86400} )) ]; then
    return
  fi
  
  # Update last purge time
  last_global_purge_time=$current_time
  
  echo "INFO: Purging PBM chunks..."
  wait_for_other_operations "backup"

  pbm config --force-resync --mongodb-uri "$PBM_MONGODB_URI"
  
  # resync wait flag might don't work
  wait_for_other_operations "backup"

  local pitr_chunks_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.backups.pitrChunks')
  local pitr_chunks_arr=$(echo "$pitr_chunks_result" | jq -r '.pitrChunks')
  if [ -z "$pitr_chunks_arr" ] || [ "$pitr_chunks_arr" = "null" ] || [ "$pitr_chunks_arr" = "[]" ]; then
    echo "INFO: No no base snapshot chunks found."
    return
  fi
  local filtered_sorted_chunks=$(echo "$pitr_chunks_arr" | jq -e 'map(select(.noBaseSnapshot == true)) | sort_by(.range.end)')
  if [ -z "$filtered_sorted_chunks" ] || [ "$filtered_sorted_chunks" = "null" ] || [ "$filtered_sorted_chunks" = "[]" ]; then
    echo "INFO: No no base snapshot chunks."
    return
  fi
  echo "INFO: No base snapshot chunks:"
  echo "$(echo $filtered_sorted_chunks | jq)"
  local first_chunk_end=$(echo "$filtered_sorted_chunks" | jq -r '.[0].range.end')
  purge_time=$(date -u -d "@${first_chunk_end}" +"%Y-%m-%dT%H:%M:%S")
  pbm cleanup --older-than $purge_time --mongodb-uri "$PBM_MONGODB_URI" --wait --yes
  echo "INFO: No base snapshot chunks cleaned up."
}

export_pbm_env_vars

set_backup_config_env

export_logs_start_time_env

trap handle_pitr_exit EXIT

sync_pbm_storage_config

sync_pbm_config_from_storage

while true; do
  wait_for_other_operations "backup"

  sync_pbm_storage_config

  enable_pitr

  purge_pitr_chunks

  upload_continuous_backup_info

  print_pbm_logs_by_event "pitr"

  export_logs_start_time_env

  sleep 30
done