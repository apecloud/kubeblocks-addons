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

# 2. get parent backup info or download backup file
mkdir -p ${DATA_DIR}
PARENT_DIR=${DATA_MOUNT_DIR}/xtrabackup-parent

# function get_last_info gets parent backup info from datasafed
function get_last_info() {
  sufix=$1
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${DP_PARENT_BACKUP_NAME}/${DP_TARGET_RELATIVE_PATH}"
  infoFile="${DP_PARENT_BACKUP_NAME}.${sufix}"
  if [ "$(datasafed list ${infoFile})" == "${infoFile}" ]; then
    echo "$(datasafed pull "/${infoFile}" - | awk '{print $1}')"
  fi
}

# function download_parent_backup_file downloads the parent backup file from datasafed
function download_parent_backup_file() {
  rm -rf ${PARENT_DIR}
  mkdir -p ${PARENT_DIR} && cd ${PARENT_DIR}
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${DP_PARENT_BACKUP_NAME}/${DP_TARGET_RELATIVE_PATH}"
  xbstreamFile="${DP_PARENT_BACKUP_NAME}.xbstream.zst"
  if [ "$(datasafed list ${xbstreamFile})" == "${xbstreamFile}" ]; then
    datasafed pull -d zstd-fastest "${xbstreamFile}" - | xbstream -x
  else
    datasafed pull "${DP_PARENT_BACKUP_NAME}.xbstream" - | xbstream -x
  fi
  xtrabackup --decompress --remove-original --target-dir=${PARENT_DIR}
}

# validate server uuid
server_uuid=$(cat ${DATA_MOUNT_DIR}/data/auto.cnf | grep server-uuid | awk -F '=' '{print $2}')
last_server_uuid=$(get_last_info "server-uuid")
if [ -n "${last_server_uuid}" ] && [ "${server_uuid}" != "${last_server_uuid}" ]; then
  echo "server uuid is not equal to server uuid of parent backup, backup target instance has changed"
  exit 1
fi

# build incremental cmd
incremental_cmd=""
last_lsn=$(get_last_info "lsn")
if [ -n "${last_lsn}" ]; then
  incremental_cmd="--incremental-lsn=${last_lsn}"
  echo "create incremental backup based on parent backup lsn"
else
  download_parent_backup_file
  incremental_cmd="--incremental-basedir=${PARENT_DIR}"
  echo "create incremental backup based on parent backup file"
fi

# set the datasafed backend base path for the current backup
# it is equal to ${DP_BACKUP_ROOT_PATH}/${DP_BACKUP_NAME}/${DP_TARGET_RELATIVE_PATH}
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
# compatible with version 0.6
if [ -f ${DATA_DIR}/mysql-bin.index ]; then
  echo "" | datasafed push - "apecloud-mysql.old"
fi

# 3. do incremental xtrabackup
TMP_DIR=${DATA_MOUNT_DIR}/xtrabackup-temp
mkdir -p ${TMP_DIR}
START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
xtrabackup --compress=zstd --backup --safe-slave-backup --slave-info --stream=xbstream \
  --host=${DP_DB_HOST} --port=${DP_DB_PORT} \
  --user=${DP_DB_USER} --password=${DP_DB_PASSWORD} \
  --datadir=${DATA_DIR} ${incremental_cmd} \
  2> >(tee ${TMP_DIR}/xtrabackup.log >&2) \
  | datasafed push - "/${DP_BACKUP_NAME}.xbstream"
# record lsn for incremental backups
cat "${TMP_DIR}/xtrabackup.log" \
  | grep "The latest check point (for incremental)" \
  | awk -F"'" '{print $2}' \
  | datasafed push - "/${DP_BACKUP_NAME}.lsn"
# record server uuid
echo "${server_uuid}" | datasafed push - "${DP_BACKUP_NAME}.server-uuid"
STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
rm -rf ${PARENT_DIR}
rm -rf ${TMP_DIR}
