#!/bin/bash
set -exo pipefail
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

# 1. download parent backup
export S3_PATH="$DP_BACKUP_ROOT_PATH/$DP_PARENT_BACKUP_NAME/$DP_TARGET_RELATIVE_PATH"
fetch_backup "$DP_PARENT_BACKUP_NAME"

# 2. upload diff backup
export S3_PATH="${DP_BACKUP_BASE_PATH}"
clickhouse-backup create_remote "$DP_BACKUP_NAME" --diff-from="${DP_PARENT_BACKUP_NAME}" || {
	DP_error_log "Clickhouse-backup create_remote $DP_BACKUP_NAME diff-from ${DP_PARENT_BACKUP_NAME} FAILED"
	exit 1
}

# 3. cleanup and save status
delete_backups_except "$DP_BACKUP_NAME"
save_backup_size
