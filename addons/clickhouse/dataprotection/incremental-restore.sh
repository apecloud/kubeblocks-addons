#!/bin/bash
set -exo pipefail

# ClickHouse Cluster Restore Strategy:
# - Jobs run on first replica in first shard, restore schema with ON CLUSTER across all shards
# - Always use 'ON CLUSTER' DDL (which will execute across all shards)
# - Only supports original topology: ordinal-0 pods in different shards, all replicas in same cluster
# - Partial replica usage not supported (e.g., shard0: ch-0-1, shard1: ch-1-0 from total ch-0-0,ch-0-1,ch-1-0,ch-1-1)

trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env
CLICKHOUSE_SECURE=false # Not support for TLS restore

# 1. download full backup
export S3_PATH="$DP_BACKUP_ROOT_PATH/$DP_BASE_BACKUP_NAME/$DP_TARGET_RELATIVE_PATH"
fetch_backup "$DP_BASE_BACKUP_NAME"

# 2. download ancestor incremental backups
IFS=',' read -r -a ANCESTOR_INCREMENTAL_BACKUP_NAMES <<<"${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}"
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
	export S3_PATH="$DP_BACKUP_ROOT_PATH/$parent_name/$DP_TARGET_RELATIVE_PATH"
	fetch_backup "$parent_name"
done

# 3. restore schema and rbac
export S3_PATH="${DP_BACKUP_BASE_PATH}"
first_entry="${ALL_COMBINED_SHARDS_POD_FQDN_LIST%%,*}"
first_component="${first_entry%%:*}"
if [[ -z "$first_component" || "$first_component" == "$first_entry" ]]; then
	DP_error_log "Invalid ALL_COMBINED_SHARDS_POD_FQDN_LIST: ${ALL_COMBINED_SHARDS_POD_FQDN_LIST}"
	exit 1
fi

schema_db="default"
schema_table="__kubeblocks_schema_ready__"
schema_timeout="${RESTORE_SCHEMA_READY_TIMEOUT_SECONDS:-1800}"
schema_interval="${RESTORE_SCHEMA_READY_CHECK_INTERVAL_SECONDS:-5}"
expected_shards=$(get_expected_shard_count "$ALL_COMBINED_SHARDS_POD_FQDN_LIST")

if [[ "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" == "${first_component}" ]]; then
	clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --schema --rbac || {
		DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
		exit 1
	}
	ch_query "CREATE TABLE IF NOT EXISTS \`${schema_db}\`.\`${schema_table}\` ON CLUSTER \`${INIT_CLUSTER_NAME}\` (shard String, finished_at DateTime) ENGINE=TinyLog" || {
		DP_error_log "Failed to create schema ready marker"
		exit 1
	}
else
	DP_log "Waiting for schema ready table on ${CLICKHOUSE_HOST}..."
	start=$(date +%s)
	while true; do
		if [[ "$(ch_query "EXISTS TABLE \`${schema_db}\`.\`${schema_table}\`")" == "1" ]]; then
			break
		fi
		now=$(date +%s)
		if [[ $((now - start)) -ge $schema_timeout ]]; then
			DP_error_log "Timeout waiting for schema ready table on ${CLICKHOUSE_HOST}"
			exit 1
		fi
		sleep "$schema_interval"
	done
fi

# 4. restore data for this pod(will automatically replicate to other pods)
clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --data || {
	DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
	exit 1
}

ch_query "INSERT INTO \`${schema_db}\`.\`${schema_table}\` (shard, finished_at) VALUES ('${CURRENT_SHARD_COMPONENT_SHORT_NAME}', now())" || {
	DP_error_log "Failed to insert shard ready marker"
	exit 1
}

ready_count=$(ch_query "SELECT countDistinct(shard) FROM clusterAllReplicas('${INIT_CLUSTER_NAME}', '${schema_db}', '${schema_table}')")
if [[ "$ready_count" -ge "$expected_shards" ]]; then
	DP_log "All shards ready (${ready_count}/${expected_shards}), dropping schema ready marker"
	ch_query "DROP TABLE IF EXISTS \`${schema_db}\`.\`${schema_table}\` ON CLUSTER \`${INIT_CLUSTER_NAME}\`" || {
		DP_log "Warning: Failed to drop schema ready marker"
	}
fi

# 5. delete local backup
backup_list=$(clickhouse-backup list)
echo "$backup_list" | awk '/local/ {print $1}' | while IFS= read -r backup_name; do
	clickhouse-backup delete local "$backup_name" || {
		echo "Clickhouse-backup delete local backup $backup_name FAILED"
	}
done

