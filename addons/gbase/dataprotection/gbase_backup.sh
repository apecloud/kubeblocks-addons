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
    sleep 1500 
    exit 1
  fi
}
trap handle_exit EXIT

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')

REMOTE_COMMANDS=$(cat <<EOF
    sudo -i -u gbase gs_probackup init -B ${DATA_DIR}/backup
    sudo -i -u gbase gs_probackup add-instance -B ${DATA_DIR}/backup/ -D /data/database/install/data/dn --instance ${DP_BACKUP_NAME} -d postgres -p 15400
    sudo -i -u gbase gs_probackup backup -B ${DATA_DIR}/backup/ -D /data/database/install/data/dn --instance ${DP_BACKUP_NAME} -d postgres -p 15400 -b FULL
EOF
)

# Execute remote backup commands via SSH
sshpass -p "${DP_DB_PASSWORD}" ssh -o StrictHostKeyChecking=no gbase@${DP_DB_HOST} "${REMOTE_COMMANDS}"

tar -czvf ${DATA_DIR}/${DP_BACKUP_NAME}.tar.gz ${DATA_DIR}/backup


datasafed push "/${DATA_DIR}/${DP_BACKUP_NAME}.tar.gz" "/${DP_BACKUP_NAME}.tar.gz"

rm -rf ${DATA_DIR}/${DP_BACKUP_NAME}.tar.gz ${DATA_DIR}/backup/
echo "Backup completed and downloaded to ${LOCAL_DEST_DIR}"

STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
