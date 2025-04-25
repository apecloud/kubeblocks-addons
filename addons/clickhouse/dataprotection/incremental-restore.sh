#!/bin/bash
set -e
set -o pipefail

# TODO tls
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

# 1. download full backup
export S3_PATH="$DP_BACKUP_ROOT_PATH/$DP_BASE_BACKUP_NAME/$DP_TARGET_RELATIVE_PATH"
fetch_backup "$DP_BASE_BACKUP_NAME"

# 2. download ancestor incremental backups
IFS=',' read -r -a ANCESTOR_INCREMENTAL_BACKUP_NAMES <<<"${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}"
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
  export S3_PATH="$DP_BACKUP_ROOT_PATH/$parent_name/$DP_TARGET_RELATIVE_PATH"
  fetch_backup "$parent_name"
done

# 3. restore schema for all pod in shard
export S3_PATH="${DP_BACKUP_BASE_PATH}"
fqdns=$(get_shard_fqdn_list)
for fqdn in $fqdns; do
  export CLICKHOUSE_HOST="$fqdn"
  clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --schema || {
    DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
    exit 1
  }
done

# 4. restore data for this pod(will automatically replicate to other pods)
export CLICKHOUSE_HOST="${DP_DB_HOST}"
clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --data || {
  DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
  exit 1
}

# 5. delete local backup
backup_list=$(clickhouse-backup list)
echo "$backup_list" | awk '/local/ {print $1}' | while IFS= read -r backup_name; do
  clickhouse-backup delete local "$backup_name" || {
    echo "Clickhouse-backup delete local backup $backup_name FAILED"
  }
done

exit 0