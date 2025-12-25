#!/bin/bash
set -exo pipefail
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env
delete_backups_except "$DP_BACKUP_NAME"

clickhouse-backup create_remote "$DP_BACKUP_NAME" || {
	DP_error_log "Clickhouse-backup create_remote $DP_BACKUP_NAME FAILED"
	exit 1
}

save_backup_size
