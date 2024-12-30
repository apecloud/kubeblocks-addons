#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"

# function change_path takes one argument, the backup name, and changes the DATASAFED_BACKEND_BASE_PATH
function change_path() {
  backup_name=$1
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${backup_name}/${DP_TARGET_RELATIVE_PATH}"
}

# 1. check base backup name
if [[ -z ${DP_BASE_BACKUP_NAME} ]]; then
  echo "DP_BASE_BACKUP_NAME is empty"
  exit 1
fi

# 2. download backup files
# download base backup file
mkdir -p ${DATA_DIR}
BASE_DIR=${DATA_MOUNT_DIR}/base
mkdir -p ${BASE_DIR} && cd ${BASE_DIR}
change_path "${DP_BASE_BACKUP_NAME}"
datasafed pull "${DP_BASE_BACKUP_NAME}.xbstream" - | xbstream -x
xtrabackup --decompress --remove-original --target-dir=${BASE_DIR}
# download parent backup files
if [ -n "${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}" ]; then
  read -r -a ANCESTOR_INCREMENTAL_BACKUP_NAMES <<< "${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES//,/ }"
fi
INCS_DIR=${DATA_MOUNT_DIR}/incs
mkdir -p ${INCS_DIR}
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
  change_path "${parent_name}"
  mkdir -p ${INCS_DIR}/${parent_name} && cd ${INCS_DIR}/${parent_name}
  datasafed pull "${parent_name}.xbstream" - | xbstream -x
  xtrabackup --decompress --remove-original --target-dir=${INCS_DIR}/${parent_name}
done
# download target backup file
change_path "${DP_BACKUP_NAME}"
mkdir -p ${INCS_DIR}/${DP_BACKUP_NAME} && cd ${INCS_DIR}/${DP_BACKUP_NAME}
datasafed pull "${DP_BACKUP_NAME}.xbstream" - | xbstream -x
xtrabackup --decompress --remove-original --target-dir=${INCS_DIR}/${DP_BACKUP_NAME}

old_signal="apecloud-mysql.old"
log_bin=${LOG_BIN}
if [ "$(datasafed list ${old_signal})" == "${old_signal}" ]; then
   log_bin="${DATA_DIR}/mysql-bin"
fi

# 3. prepare data
xtrabackup --prepare --apply-log-only --target-dir=${BASE_DIR}
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
  xtrabackup --prepare --apply-log-only --target-dir=${BASE_DIR} --incremental-dir=${INCS_DIR}/${parent_name}
done
xtrabackup --prepare --target-dir=${BASE_DIR} --incremental-dir=${INCS_DIR}/${DP_BACKUP_NAME}

# 4. restore
xtrabackup --move-back --target-dir=${BASE_DIR} --datadir=${DATA_DIR}/ --log-bin=${log_bin}
touch ${DATA_DIR}/${SIGNAL_FILE}
rm -rf ${BASE_DIR}
rm -rf ${INCS_DIR}
chmod -R 0777 ${DATA_DIR}
echo "Restore completed!"
