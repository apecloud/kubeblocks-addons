#!/bin/bash
set -exo pipefail

# Downloads full backup + ancestor incremental backups before restore
# Supports: standalone (single node) and cluster (multi-shard) topologies, each typology only can use its backup

trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

# 1. Download full (base) backup
export S3_PATH="$DP_BACKUP_ROOT_PATH/$DP_BASE_BACKUP_NAME/$DP_TARGET_RELATIVE_PATH"
fetch_backup "$DP_BASE_BACKUP_NAME"
downloaded_backups=("$DP_BASE_BACKUP_NAME")

# 2. Download ancestor incremental backups
IFS=',' read -r -a ancestors <<<"${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}"
for parent_name in "${ancestors[@]}"; do
	[[ -z "$parent_name" ]] && continue
	export S3_PATH="$DP_BACKUP_ROOT_PATH/$parent_name/$DP_TARGET_RELATIVE_PATH"
	stage_required_backup_metadata "$S3_PATH" "${downloaded_backups[@]}" || exit 1
	fetch_backup "$parent_name"
	downloaded_backups+=("$parent_name")
done

# 3. Detect topology mode: standalone or cluster
export S3_PATH="${DP_BACKUP_BASE_PATH}"
stage_required_backup_metadata "$S3_PATH" "${downloaded_backups[@]}" || exit 1
mode_info=$(detect_restore_mode) || exit 1

# 4. Restore schema + data + marker
do_restore "${DP_BACKUP_NAME}" "$mode_info" || exit 1

# 5. Cleanup all local backups
delete_backups_except ""
