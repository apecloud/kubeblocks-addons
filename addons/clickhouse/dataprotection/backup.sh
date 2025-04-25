#!/bin/bash
set -e
set -o pipefail

# TODO tls
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env
delete_backups_except "$DP_BACKUP_NAME"

clickhouse-backup create_remote "$DP_BACKUP_NAME" || {
  DP_error_log "Clickhouse-backup create_remote $DP_BACKUP_NAME FAILED"
  exit 1
}

shard_base_dir=$(dirname "${DP_BACKUP_BASE_PATH}")
export DATASAFED_BACKEND_BASE_PATH="$shard_base_dir"
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
BACKUP_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
DP_save_backup_status_info "$BACKUP_SIZE"

exit 0