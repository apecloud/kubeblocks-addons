#!/bin/bash

set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

START_TIME=$(get_current_time)
echo "${DP_DB_PASSWORD}" | pg_basebackup -Ft -Pv -c fast -Xf -D - -h "${DP_DB_HOST}" -U "${DP_DB_USER}" -W | datasafed push -z zstd-fastest - "/${DP_BACKUP_NAME}.tar.zst"

# stat and save the backup information
stat_and_save_backup_info "$START_TIME"