#!/bin/bash
# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise

set -e
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
restore_time=`date -d "${DP_RESTORE_TIME}" +%s`
INIT_ARCHIVE_PATH=${BACKUP_DIR}/INIT_ARCHIVE_BACKUPS
mkdir -p "${INIT_ARCHIVE_PATH}"

function DP_log() {
  local curr_date=
  echo "$(date -u '+%Y-%m-%d %H:%M:%S') INFO: $msg"
}

# The list files are read-only inputs. ShellCheck mistakes error-path cleanup
# inside these read loops for concurrent writes to the same stream.
# shellcheck disable=SC2094
function prepare_archive_restore_chains() {
  local database_paths_file log_paths_file database db_name metadata_file
  local base_backup_path start_log_timestamp closest_timestamp_diff
  local current_path current_timestamp timestamp_diff index file file_name backup_time local_file
  database_paths_file=$(mktemp "${INIT_ARCHIVE_PATH}/database-paths.XXXXXX") || return 1
  log_paths_file=$(mktemp "${INIT_ARCHIVE_PATH}/log-paths.XXXXXX") || {
    rm -f "$database_paths_file"
    return 1
  }
  if ! datasafed_list_paths_to_file "$database_paths_file" -d /; then
    rm -f "$database_paths_file" "$log_paths_file"
    return 1
  fi

  while IFS= read -r -d '' database; do
    database=${database#/}
    database=${database%/}
    db_name=${database##*/}
    if [ -z "$db_name" ]; then
      DP_error_log "empty database directory returned by datasafed"
      rm -f "$database_paths_file" "$log_paths_file"
      return 1
    fi

    metadata_file="${INIT_ARCHIVE_PATH}/${db_name}.basefull.info"
    if ! datasafed pull "${db_name}.basefull.info" "$metadata_file"; then
      rm -f "$database_paths_file" "$log_paths_file"
      return 1
    fi
    if ! archive_metadata_load_file "$metadata_file"; then
      DP_error_log "invalid archive metadata for database ${db_name}"
      rm -f "$database_paths_file" "$log_paths_file"
      return 1
    fi

    base_backup_path=""
    start_log_timestamp=""
    closest_timestamp_diff=9999999999
    for index in "${!ARCHIVE_METADATA_PATHS[@]}"; do
      current_path=${ARCHIVE_METADATA_PATHS[$index]}
      current_timestamp=${ARCHIVE_METADATA_FULL_TIMESTAMPS[$index]}
      if [[ "$current_timestamp" -le "$restore_time" ]]; then
        timestamp_diff=$((restore_time - current_timestamp))
        if [[ "$timestamp_diff" -lt "$closest_timestamp_diff" ]]; then
          base_backup_path=$current_path
          closest_timestamp_diff=$timestamp_diff
          start_log_timestamp=${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[$index]}
        fi
      fi
    done
    if [ -z "$base_backup_path" ] || ! [[ "$start_log_timestamp" =~ ^[0-9]+$ ]]; then
      DP_error_log "no complete base/log metadata before restore time for database ${db_name}"
      rm -f "$database_paths_file" "$log_paths_file"
      return 1
    fi

    if [[ "$base_backup_path" == "$DP_BACKUP_NAME/"* ]]; then
      if ! datasafed pull -d zstd-fastest "${base_backup_path#"$DP_BACKUP_NAME/"}" "${INIT_ARCHIVE_PATH}/${db_name}.basefull.bak"; then
        rm -f "$database_paths_file" "$log_paths_file"
        return 1
      fi
    else
      export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH%/*}"
      if ! datasafed pull -d zstd-fastest "$base_backup_path" "${INIT_ARCHIVE_PATH}/${db_name}.basefull.bak"; then
        export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
        rm -f "$database_paths_file" "$log_paths_file"
        return 1
      fi
      export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
    fi

    if [[ ! -f "${INIT_ARCHIVE_PATH}/${db_name}.basefull.bak" ]]; then
      DP_error_log "basefull backup file ${INIT_ARCHIVE_PATH}/${db_name}.basefull.bak not found"
      rm -f "$database_paths_file" "$log_paths_file"
      return 1
    fi
    archive_chain_format_entry "${db_name}.basefull.bak" > "${INIT_ARCHIVE_PATH}/${db_name}.chain"

    if ! datasafed_list_paths_to_file "$log_paths_file" -f "/${database}" -s mtime; then
      rm -f "$database_paths_file" "$log_paths_file"
      return 1
    fi
    while IFS= read -r -d '' file; do
      file_name=${file##*/}
      if [[ "$file_name" =~ \.basefull\.[0-9]+\.bak\.zst$ ]]; then
        continue
      fi
      if [[ "$file_name" =~ \.([0-9]+)\.bak\.zst$ ]]; then
        backup_time=${BASH_REMATCH[1]}
      else
        backup_time=
      fi
      if ! [[ "$backup_time" =~ ^[0-9]+$ ]]; then
        DP_error_log "skip unexpected file ${file}: extracted backup time '${backup_time}' is not numeric, not a log backup"
        continue
      fi
      if [[ "$backup_time" -lt "$start_log_timestamp" ]]; then
        continue
      fi

      DP_log "start to pull the archive ${file}"
      local_file=${file#/}
      mkdir -p "$(dirname "${INIT_ARCHIVE_PATH}/${local_file}")"
      if ! datasafed pull -d zstd-fastest "$file" "${INIT_ARCHIVE_PATH}/${local_file}"; then
        rm -f "$database_paths_file" "$log_paths_file"
        return 1
      fi
      archive_chain_format_entry "$local_file" >> "${INIT_ARCHIVE_PATH}/${db_name}.chain"
      DP_log "finished."
      if [[ $backup_time -gt $restore_time ]]; then
         DP_log "exit when reaching the target time log."
         break
      fi
    done < "$log_paths_file"
  done < "$database_paths_file"
  rm -f "$database_paths_file" "$log_paths_file"
}

prepare_archive_restore_chains

set +e
datasafed pull /server_login_names.sql "${INIT_ARCHIVE_PATH}/server_login_names.sql"
set -e

db_restore_time=$(date -d "${DP_RESTORE_TIME}" '+%Y-%m-%d %H:%M:%S')
echo "${db_restore_time}" > "${BACKUP_DIR}/.restore_archive"
