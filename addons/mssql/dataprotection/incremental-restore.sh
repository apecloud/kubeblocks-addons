# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

set -e
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function download_backups_for_incremental() {
  local backup_name=$1
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${backup_name}/${DP_TARGET_RELATIVE_PATH}"
  download_backups "${backup_name}"
}

# 1. download base backup
download_backups_for_incremental ${DP_BASE_BACKUP_NAME}
# download certificates from base full backup
download_certificates

# 2. download ancestor incremental backups
IFS=',' read -r -a ANCESTOR_INCREMENTAL_BACKUP_NAMES <<< "${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES}"
for parent_name in "${ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}"; do
  download_backups_for_incremental "${parent_name}"
done

# 3. download current incremental backup
download_backups_for_incremental ${DP_BACKUP_NAME}

# 4. set the backup chain for the databases
# 4.1 get the databases from latest backup
declare -A completed_chains

function set_database_backup_chain() {
  local backup_name=${1:?"missing backup name"}
  local file=${2:?"missing file name"}
  local append=${3:-true}
  local file_name database_name chain_file
  file_name=$(basename "$file")
  local is_full=false
  if [[ "${file_name}" == *".sql" ]]; then
    return
  fi
  if [[ "${file_name}" == *".full.bak" ]]; then
    database_name=${file_name%.full.bak}
    is_full=true
  else
    database_name=${file_name%.incremental.bak}
  fi
  if [[ -v completed_chains["${database_name}"] ]]; then
    DP_log "skip ${database_name} because it is completed from backup ${backup_name}."
    return
  fi
  if [[ "${is_full}" == "true" ]]; then
     completed_chains["${database_name}"]=true
  fi
  chain_file="${BACKUP_DIR}/INIT_BACKUPS/${database_name}.chain"
  if [[ "${append}" == "true" ]]; then
    DP_log "add ${backup_name}/${file_name} to ${chain_file}"
    append_chain_entry "$chain_file" "${backup_name}/${file_name}"
  else
   if [ -f "$chain_file" ]; then
      DP_log "add ${backup_name}/${file_name} to the head of ${chain_file}"
      prepend_chain_entry "$chain_file" "${backup_name}/${file_name}"
   fi
  fi
}

if ! load_local_files "${BACKUP_DIR}/INIT_BACKUPS/${DP_BACKUP_NAME}"; then
  DP_log "failed to enumerate files for backup ${DP_BACKUP_NAME}"
  exit 1
fi
for file in "${DP_LOCAL_FILES[@]}"; do
   set_database_backup_chain "${DP_BACKUP_NAME}" "${file}"
done

if [ -f "${BACKUP_DIR}/INIT_BACKUPS/${DP_BACKUP_NAME}/server_login_names.sql" ]; then
   cp "${BACKUP_DIR}/INIT_BACKUPS/${DP_BACKUP_NAME}/server_login_names.sql" "${BACKUP_DIR}/INIT_BACKUPS/server_login_names.sql"
fi

# 4.2 set the backup chain for the databases which are in the latest backup
for ((i=${#ANCESTOR_INCREMENTAL_BACKUP_NAMES[@]}-1; i>=0; i--)); do
  backup_name="${ANCESTOR_INCREMENTAL_BACKUP_NAMES[$i]}"
  if ! load_local_files "${BACKUP_DIR}/INIT_BACKUPS/${backup_name}"; then
    DP_log "failed to enumerate files for backup ${backup_name}"
    exit 1
  fi
  for file in "${DP_LOCAL_FILES[@]}"; do
     set_database_backup_chain "${backup_name}" "${file}" "false"
  done
done

if ! load_local_files "${BACKUP_DIR}/INIT_BACKUPS/${DP_BASE_BACKUP_NAME}"; then
  DP_log "failed to enumerate files for backup ${DP_BASE_BACKUP_NAME}"
  exit 1
fi
for file in "${DP_LOCAL_FILES[@]}"; do
   set_database_backup_chain "${DP_BASE_BACKUP_NAME}" "${file}" "false"
done

if [ "${REBUILD_INSTANCE}" == "true" ]; then
  echo "" > "${BACKUP_DIR}/.rebuild"
else
  echo "" > "${BACKUP_DIR}/.restore"
fi
