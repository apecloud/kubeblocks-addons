#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"

# function change_backend_path changes the DATASAFED_BACKEND_BASE_PATH by backup name
function change_backend_path() {
  backup_name=$1
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${backup_name}/${DP_TARGET_RELATIVE_PATH}"
}

# function download_backup_file downloads a backup file to a local target directory
function download_backup_file() {
  backup_name=$1
  local_target_dir=$2
  mkdir -p ${local_target_dir} && cd ${local_target_dir}
  change_backend_path "${backup_name}"
  xbstreamFile="${backup_name}.xbstream.zst"
  if [ "$(datasafed list ${xbstreamFile})" == "${xbstreamFile}" ]; then
    datasafed pull -d zstd-fastest "${xbstreamFile}" - | xbstream -x
  else
    datasafed pull "${backup_name}.xbstream" - | xbstream -x
  fi
  xtrabackup --decompress --remove-original --target-dir=${local_target_dir}
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
download_backup_file "${DP_BASE_BACKUP_NAME}" "${BASE_DIR}"
# download parent backup files
if [ -n "${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}" ]; then
  read -r -a ANCESTOR_INCREMENTAL_BACKUP_NAMES <<< "${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES//,/ }"
fi
INCS_DIR=${DATA_MOUNT_DIR}/incs
mkdir -p ${INCS_DIR}
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
  download_backup_file "${parent_name}" "${INCS_DIR}/${parent_name}"
done
# download target backup file
download_backup_file "${DP_BACKUP_NAME}" "${INCS_DIR}/${DP_BACKUP_NAME}"

# 3. prepare data
xtrabackup --prepare --apply-log-only --target-dir=${BASE_DIR}
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
  xtrabackup --prepare --apply-log-only --target-dir=${BASE_DIR} --incremental-dir=${INCS_DIR}/${parent_name}
done
xtrabackup --prepare --target-dir=${BASE_DIR} --incremental-dir=${INCS_DIR}/${DP_BACKUP_NAME}

# 4. restore
xtrabackup --move-back --target-dir=${BASE_DIR} --datadir=${DATA_DIR}/ --log-bin=${log_bin}
touch ${DATA_DIR}/.xtrabackup_restore
if [ "${BACKUP_FOR_STANDBY}" != "true" ]; then
   touch ${DATA_DIR}/.restore_new_cluster
fi
rm -rf ${BASE_DIR}
rm -rf ${INCS_DIR}
chmod -R 0777 ${DATA_DIR}
echo "Restore completed!"
