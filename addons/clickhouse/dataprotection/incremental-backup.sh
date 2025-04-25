#!/bin/bash
set -e
set -o pipefail

# TODO tls
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

# 1. download parent backup and
export S3_PATH="$DP_BACKUP_ROOT_PATH/$DP_PARENT_BACKUP_NAME/$DP_TARGET_RELATIVE_PATH"
fetch_backup "$DP_PARENT_BACKUP_NAME"

# 2. upload diff backup
export S3_PATH="${DP_BACKUP_BASE_PATH}"
clickhouse-backup create_remote "$DP_BACKUP_NAME" --diff-from="${DP_PARENT_BACKUP_NAME}" || {
  DP_error_log "Clickhouse-backup create_remote $DP_BACKUP_NAME diff-from ${DP_PARENT_BACKUP_NAME} FAILED"
  exit 1
}

# 3. delete non latest backup
delete_backups_except "$DP_BACKUP_NAME"

# 4. save backup status info
shard_base_dir=$(dirname "${DP_BACKUP_BASE_PATH}")
export DATASAFED_BACKEND_BASE_PATH="$shard_base_dir"
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
BACKUP_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
DP_save_backup_status_info "$BACKUP_SIZE"

exit 0