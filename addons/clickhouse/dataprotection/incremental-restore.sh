#!/bin/bash
set -exo pipefail

# Downloads full backup + ancestor incremental backups before restore
# Supports: standalone (single node) and cluster (multi-shard) topologies, each typology only can use its backup

trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

if [[ "${CLICKHOUSE_SECURE}" = "true" ]]; then
	DP_error_log "ClickHouse restore does not support TLS"
	exit 1
fi

# 1. Download full (base) backup
export S3_PATH="$DP_BACKUP_ROOT_PATH/$DP_BASE_BACKUP_NAME/$DP_TARGET_RELATIVE_PATH"
fetch_backup "$DP_BASE_BACKUP_NAME"

# 2. Download ancestor incremental backups
IFS=',' read -r -a ancestors <<<"${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}"
for parent_name in "${ancestors[@]}"; do
	export S3_PATH="$DP_BACKUP_ROOT_PATH/$parent_name/$DP_TARGET_RELATIVE_PATH"
	fetch_backup "$parent_name"
done

# 3. Detect topology mode: standalone (no ':' in FQDN) or cluster
export S3_PATH="${DP_BACKUP_BASE_PATH}"
first_entry="${ALL_COMBINED_SHARDS_POD_FQDN_LIST%%,*}"
first_component="${first_entry%%:*}"
if [[ -z "$first_component" ]]; then
	DP_error_log "Invalid ALL_COMBINED_SHARDS_POD_FQDN_LIST"
	exit 1
fi
if [[ "$first_component" == "$first_entry" ]]; then
	mode_info="standalone"
	DP_log "Standalone mode detected"
else
	mode_info="cluster:$first_component"
fi

# 4. Restore schema + data + marker
do_restore "${DP_BACKUP_NAME}" "$mode_info" || exit 1

# 5. Cleanup all local backups
delete_backups_except ""
