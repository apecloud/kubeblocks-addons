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

# 1. check parent backup name
if [[ -z ${DP_PARENT_BACKUP_NAME} ]]; then
  echo "DP_PARENT_BACKUP_NAME is empty"
  exit 1
fi

# 2. get parent backup
mkdir -p ${DATA_DIR}
PARENT_DIR=${DATA_MOUNT_DIR}/xtrabackup-parent
rm -rf ${PARENT_DIR}
mkdir -p ${PARENT_DIR} && cd ${PARENT_DIR}
# set the datasafed backend base path for the parent backup
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${DP_PARENT_BACKUP_NAME}/${DP_TARGET_RELATIVE_PATH}"
datasafed pull "${DP_PARENT_BACKUP_NAME}.xbstream" - | xbstream -x
xtrabackup --decompress --remove-original --target-dir=${PARENT_DIR}

# set the datasafed backend base path for the current backup
# it is equal to ${DP_BACKUP_ROOT_PATH}/${DP_BACKUP_NAME}/${DP_TARGET_RELATIVE_PATH}
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
# compatible with version 0.6
if [ -f ${DATA_DIR}/mysql-bin.index ]; then
  echo "" | datasafed push - "apecloud-mysql.old"
fi

# 3. do incremental xtrabackup
START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
xtrabackup --compress=zstd --backup --safe-slave-backup --slave-info --stream=xbstream \
  --host=${DP_DB_HOST} --port=${DP_DB_PORT} \
  --user=${DP_DB_USER} --password=${DP_DB_PASSWORD} \
  --datadir=${DATA_DIR} --incremental-basedir=${PARENT_DIR} | datasafed push - "/${DP_BACKUP_NAME}.xbstream"
STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
rm -rf ${PARENT_DIR}
