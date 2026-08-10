# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

set -e
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

download_backups "${DP_BACKUP_NAME}"
download_certificates

# set the backup chain
if ! load_local_files "${BACKUP_DIR}/INIT_BACKUPS/${DP_BACKUP_NAME}"; then
  echo "failed to enumerate downloaded backup files" >&2
  exit 1
fi
for file in "${DP_LOCAL_FILES[@]}"; do
   file_name=$(basename "$file")
   database_name=${file_name%.full.bak}
   database_name=${database_name%.incremental.bak}
   if [[ "${file_name}" == *".sql" ]]; then
      continue
   fi
   append_chain_entry "${BACKUP_DIR}/INIT_BACKUPS/${database_name}.chain" "${DP_BACKUP_NAME}/${file_name}"
done

if [ -f "${BACKUP_DIR}/INIT_BACKUPS/${DP_BACKUP_NAME}/server_login_names.sql" ]; then
   cp "${BACKUP_DIR}/INIT_BACKUPS/${DP_BACKUP_NAME}/server_login_names.sql" "${BACKUP_DIR}/INIT_BACKUPS/server_login_names.sql"
fi


if [ "${REBUILD_INSTANCE}" == "true" ]; then
  echo "" > "${BACKUP_DIR}/.rebuild"
else
  echo "" > "${BACKUP_DIR}/.restore"
fi
