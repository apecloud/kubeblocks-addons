#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

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

lock_per_table_ddl=""
if [ "${IMAGE_TAG}" == "2.4" ]; then
  lock_per_table_ddl="--lock-ddl-per-table"
fi

if [ ! -z "${MYSQL_ADMIN_PASSWORD}" ]; then
  DP_DB_PASSWORD=${MYSQL_ADMIN_PASSWORD}
  DP_DB_USER=${MYSQL_ADMIN_USER}
fi

TMP_DIR=${MYSQL_DIR}/xtrabackup-temp
mkdir -p ${TMP_DIR}
xtrabackup --backup --safe-slave-backup --slave-info ${lock_per_table_ddl} --stream=xbstream \
  --host=${DP_DB_HOST} --user=${DP_DB_USER} --password=${DP_DB_PASSWORD} --datadir=${DATA_DIR} \
  2> >(tee ${TMP_DIR}/xtrabackup.log >&2) \
  | datasafed push -z zstd-fastest - "/${DP_BACKUP_NAME}.xbstream.zst"
# record lsn for incremental backups
cat "${TMP_DIR}/xtrabackup.log" \
  | grep "The latest check point (for incremental)" \
  | awk -F"'" '{print $2}' \
  | datasafed push - "/${DP_BACKUP_NAME}.lsn"
# record server uuid
cat ${MYSQL_DIR}/data/auto.cnf | grep server-uuid | awk -F '=' '{print $2}' | datasafed push - "${DP_BACKUP_NAME}.server-uuid"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}"
rm -rf ${TMP_DIR}