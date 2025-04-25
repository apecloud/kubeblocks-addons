#!/bin/bash
set -exo pipefail

# TODO tls
trap handle_exit EXIT
generate_backup_config
set_clickhouse_backup_config_env

fqdns=$(get_shard_fqdn_list)
for fqdn in $fqdns; do
  export CLICKHOUSE_HOST="$fqdn"
  clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --schema || {
    DP_error_log "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
    exit 1
  }
done

export CLICKHOUSE_HOST="${DP_DB_HOST}"
clickhouse-backup restore_remote "${DP_BACKUP_NAME}" --data || {
  DP_error_log  "Clickhouse-backup restore_remote backup $DP_BACKUP_NAME FAILED"
  exit 1
}

clickhouse-backup delete local "${DP_BACKUP_NAME}" || {
 DP_error_log  "Clickhouse-backup delete local backup $DP_BACKUP_NAME FAILED"
 exit 1
}

exit 0
