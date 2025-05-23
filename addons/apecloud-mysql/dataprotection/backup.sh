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

# compatible with version 0.6
if [ -f ${DATA_DIR}/mysql-bin.index ]; then
  echo "" | datasafed push - "apecloud-mysql.old"
fi
# do xtrabackup
TMP_DIR=${DATA_MOUNT_DIR}/xtrabackup-temp
mkdir -p ${TMP_DIR}
START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
xtrabackup --compress=zstd --backup --safe-slave-backup --slave-info --stream=xbstream \
  --host=${DP_DB_HOST} --port=${DP_DB_PORT} \
  --user=${DP_DB_USER} --password=${DP_DB_PASSWORD} --datadir=${DATA_DIR} \
  2> >(tee ${TMP_DIR}/xtrabackup.log >&2) \
  | datasafed push - "/${DP_BACKUP_NAME}.xbstream"
# record lsn for incremental backups
cat "${TMP_DIR}/xtrabackup.log" \
  | grep "The latest check point (for incremental)" \
  | awk -F"'" '{print $2}' \
  | datasafed push - "/${DP_BACKUP_NAME}.lsn"
# record server uuid
cat ${DATA_MOUNT_DIR}/data/auto.cnf | grep server-uuid | awk -F '=' '{print $2}' | datasafed push - "${DP_BACKUP_NAME}.server-uuid"
STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
rm -rf ${TMP_DIR}
