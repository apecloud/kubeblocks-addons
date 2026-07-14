#!/bin/bash

# When doing point-in-time recovery for deployments with sharded collections, PBM only writes data to existing ones and does not support creating new collections.
# Therefore, whenever you create a new sharded collection, make a new backup for it to be included there. Ref: https://docs.percona.com/percona-backup-mongodb/usage/pitr-physical.html#post-restore-steps
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
  local current_purge_interval_seconds
  current_pitr_enabled=$(echo "$current_pitr_conf" | jq -r '.enabled // false')
  current_oplog_span_min=$(echo "$current_pitr_conf" | jq -r '.oplog_span_min // empty')
  current_pitr_compression=$(echo "$current_pitr_conf" | jq -r '.compression // empty')
  current_purge_interval_seconds=$(echo "$current_pitr_conf" | jq -r '.purge_interval_seconds // empty')

  if [ -n "${PBM_STORAGE_CONFIG_TOKEN:-}" ] || [ "$current_pitr_enabled" != "true" ] || [ "$current_oplog_span_min" != "$PBM_OPLOG_SPAN_MIN_MINUTES" ] || [ "$current_pitr_compression" != "$PBM_COMPRESSION" ] || [ "$current_purge_interval_seconds" != "$PBM_PURGE_INTERVAL_SECONDS" ]; then
    echo "INFO: Applying desired PITR configuration through syncer..."
    local args=(pitr enable --oplog-span-min "$PBM_OPLOG_SPAN_MIN_MINUTES" --compression "$PBM_COMPRESSION" --purge-interval-seconds "$PBM_PURGE_INTERVAL_SECONDS")
    if [ -n "${PBM_STORAGE_CONFIG_TOKEN:-}" ]; then
      args+=(--storage-config-token "$PBM_STORAGE_CONFIG_TOKEN")
    fi
    syncerctl_cmd "${args[@]}"
    if [ -n "${PBM_STORAGE_CONFIG_FILE:-}" ]; then
      rm -f "$PBM_STORAGE_CONFIG_FILE"
      PBM_STORAGE_CONFIG_FILE=""
      PBM_STORAGE_CONFIG_TOKEN=""
    fi
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
  echo "INFO: Continuous backup result:"
  echo "$(echo "$status_result" | jq)"
  if save_syncer_backup_info "$status_result"; then
    echo "INFO: Continuous backup info uploaded."
  fi
}

set_backup_config_env

trap handle_pitr_exit EXIT

# Apply storage once through the first PITR enable call. Re-applying storage in
# the loop clears PBM PITR settings and restarts slicing before chunks mature.
prepare_pbm_operation_storage_config

while true; do
  enable_pitr

  upload_continuous_backup_info

  sleep 30
done