#!/bin/bash
set -exo pipefail

# ClickHouse Cluster Restore Strategy:
# - Jobs run on first replica per shard, restore schema to all replicas in shard
# - Cannot use 'ON CLUSTER' DDL (which will execute across all shards)
# - Only supports original topology: ordinal-0 pods in different shards, all replicas in same cluster
# - Partial replica usage not supported (e.g., shard0: ch-0-1, shard1: ch-1-0 from total ch-0-0,ch-0-1,ch-1-0,ch-1-1)

# TODO tls
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

fqdns=$(get_shard_fqdn_list)
IFS=',' read -r -a fqdn_array <<<"$fqdns"
for fqdn in "${fqdn_array[@]}"; do
  export CLICKHOUSE_HOST="$fqdn"
  clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --schema || {
    DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
    exit 1
  }
done

# https://github.com/Altinity/clickhouse-backup/issues/948 sync rbac by keeper
export CLICKHOUSE_HOST="${DP_DB_HOST}"
clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --data --rbac || {
  DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
  exit 1
}

clickhouse-backup delete local "${DP_BACKUP_NAME}" || {
  DP_error_log "Clickhouse-backup delete local backup $DP_BACKUP_NAME FAILED"
  exit 1
}

exit 0
