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

sudo -i -u gbase gs_probackup init -B /${DATA_DIR}/backup
sudo -i -u gbase gs_probackup add-instance -B /${DATA_DIR}/backup/ -D /data/database/install/data/dn --instance kb_backup
sudo -i -u gbase gs_probackup backup -B /${DATA_DIR}/backup --instance kb_backup -b FULL 
# gs_probackup backup --remote-host=192.168.20.69 --remote-user=gbase --remote-path=/opt/database/install/app/bin/gs_probackup   -B  /data/backup  --instance kb_backup -b FULL -p 15400 -d gbase 


tar -czvf /${DATA_DIR}/${DP_BACKUP_NAME}.tar.gz  /${DATA_DIR}/backup 
datasafed push "/${DATA_DIR}/${DP_BACKUP_NAME}.tar.gz" "/${DP_BACKUP_NAME}.tar.gz"

STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
