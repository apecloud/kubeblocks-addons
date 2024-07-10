#!/bin/bash
set -e
set -o pipefail

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

if [ -d "/home/gbase/backup" ]; then
    sudo rm -rf /home/gbase/backup
fi
sudo -u gbase mkdir -p /${DATA_DIR}/backup

/home/gbase/gbase_db/app/bin/gs_dumpall -f /home/gbase/backup/backup.sql -p ${DP_DB_PORT} -h ${DP_DB_HOST} -U ${DP_DB_USER} -W ${DP_DB_PASSWORD}

tar -C /home/gbase/backup/ -czvf /home/gbase/${DP_BACKUP_NAME}.tar.gz backup.sql
datasafed push "/home/gbase/${DP_BACKUP_NAME}.tar.gz"

STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
