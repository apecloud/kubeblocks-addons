#!/bin/bash
set -exo pipefail

# Supports: standalone (single node) and sharded (multi-shard) layouts
# Strategy: first shard restores schema with ON CLUSTER, others wait for sync

trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

if [[ "${CLICKHOUSE_SECURE}" = "true" ]]; then
	DP_error_log "ClickHouse restore does not support TLS"
	exit 1
fi

# 1. Detect layout mode: standalone (no ':' in FQDN) or sharded
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

# 2. Restore schema + data + marker
do_restore "${DP_BACKUP_NAME}" "$mode_info" || exit 1

# 3. Cleanup local backups
delete_backups_except ""
