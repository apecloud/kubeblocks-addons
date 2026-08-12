# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

set -e
# ${database}.basefull.info: Records all full backup paths, timestamps, and the first subsequent log backup path for the database
# format: full_backup_path timestamp log_backup_path
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export NEXT_LOG_BACKUP_PLACEHOLDER="NEXT_LOG_BACKUP_PLACEHOLDER"

# Auto-detect sqlcmd path: mssql-tools18 (2022) vs mssql-tools (2019)
if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi

sql_cmd="$SQLCMD -S ${DP_DB_HOST} -U ${DP_DB_USER}  -C -P ${DP_DB_PASSWORD} -h-1 -W -x"
GLOBAL_END_TIME=0
IS_INIT_BACKUP=false
DP_CERTIFICATE_NAME="dbm_certificate"

DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}

function backup_certificate() {
  # backup certificate
  DP_log "backup certificate ${DP_CERTIFICATE_NAME}"
  local certificate_sql certificate_literal password_literal
  certificate_sql=$(quote_tsql_identifier "$DP_CERTIFICATE_NAME")
  certificate_literal=$(quote_tsql_literal "$DP_CERTIFICATE_NAME")
  password_literal=$(quote_tsql_literal "$MSSQL_PRIVATE_ENCRYPTION_PASSWORD")
  certificate_check=$(${sql_cmd} -Q "select * from sys.certificates where name = ${certificate_literal}")
  if [ -z "${certificate_check}" ];then
    DP_error_log "certificate ${DP_CERTIFICATE_NAME} not exist"
    exit 1
  fi

  # Detect SQL Server major version: 16=2022 (supports PFX), 15=2019 (PVK/CER only)
  local mssql_major_version
  mssql_major_version=$(${sql_cmd} -Q "SET NOCOUNT ON; SELECT CAST(SERVERPROPERTY('ProductMajorVersion') AS INT)" 2>/dev/null | tr -d '[:space:]')

  if [ "${mssql_major_version:-16}" -ge 16 ]; then
    local pfx_path_sql
    pfx_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pfx")
    backup_sql=$(cat <<EOF
BACKUP CERTIFICATE ${certificate_sql} TO FILE = ${pfx_path_sql}
WITH
    FORMAT = 'PFX',
    PRIVATE KEY (
ENCRYPTION BY PASSWORD = ${password_literal},
ALGORITHM = 'AES_256'
    )
EOF
)
    ${sql_cmd} -Q "${backup_sql}"
    if [[ $? -ne 0 ]]; then
      DP_error_log "backup certificate ${DP_CERTIFICATE_NAME} failed (PFX)"
      exit 1
    fi
    datasafed push "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pfx" "/${DP_CERTIFICATE_NAME}.pfx"
  else
    # SQL Server 2019: use CER + PVK format
    local cer_path_sql pvk_path_sql
    cer_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.cer")
    pvk_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pvk")
    backup_sql=$(cat <<EOF
BACKUP CERTIFICATE ${certificate_sql} TO FILE = ${cer_path_sql}
WITH PRIVATE KEY (
    FILE = ${pvk_path_sql},
    ENCRYPTION BY PASSWORD = ${password_literal}
)
EOF
)
    ${sql_cmd} -Q "${backup_sql}"
    if [[ $? -ne 0 ]]; then
      DP_error_log "backup certificate ${DP_CERTIFICATE_NAME} failed (PVK/CER)"
      exit 1
    fi
    datasafed push "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.cer" "/${DP_CERTIFICATE_NAME}.cer"
    datasafed push "${BACKUP_DIR}/${DP_BACKUP_NAME}/${DP_CERTIFICATE_NAME}.pvk" "/${DP_CERTIFICATE_NAME}.pvk"
  fi
  echo ${MSSQL_PRIVATE_ENCRYPTION_PASSWORD} | datasafed push - "${DP_CERTIFICATE_NAME}.password"
}

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
function DP_save_backup_status_info() {
  local totalSize=$1
  local startTime=$2
  local stopTime=$3
  local timeZone=$4
  local extras=$5
  local timeZoneStr=""
  if [ ! -z ${timeZone} ]; then
    timeZoneStr=",\"timeZone\":\"${timeZone}\""
  fi
  if [ -z "${stopTime}" ]; then
    echo "{\"totalSize\":\"${totalSize}\"}" >${DP_BACKUP_INFO_FILE}
  elif [ -z "${startTime}" ]; then
    echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"end\":\"${stopTime}\"${timeZoneStr}}}" >${DP_BACKUP_INFO_FILE}
  else
    echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"start\":\"${startTime}\",\"end\":\"${stopTime}\"${timeZoneStr}}}" >${DP_BACKUP_INFO_FILE}
  fi
}

function check_is_init_transaction_backup() {
   local paths_file
   paths_file=$(mktemp /tmp/mssql-archive-init.XXXXXX) || return 1
   if ! datasafed_list_paths_to_file "$paths_file" -f / --recursive; then
      rm -f "$paths_file"
      return 1
   fi
   if [[ -s "$paths_file" ]]; then
      IS_INIT_BACKUP=false
   else
      backup_certificate
      touch full.signal
      last_backup_timestamp=$(get_last_backup_timestamp_from_full_backup)
      datasafed push full.signal "full.${last_backup_timestamp}.signal"
      rm -f full.signal
      IS_INIT_BACKUP=true
   fi
   rm -f "$paths_file"
}

function get_log_backup_timestamp() {
  local database_name=${1:?"missing database name"}
  local database_literal
  database_literal=$(quote_tsql_literal "$database_name")
  backup_time=$(${sql_cmd} -d msdb -Q "SET NOCOUNT ON;select TOP 1 backup_start_date from backupset where name=${database_literal} and type='L' order by backup_set_id desc" )
  if [[ "${backup_time}" == *"Msg "* ]]; then
    echo 0
  else
    echo $(date -d "${backup_time%.*}" +%s)
  fi
}

function get_full_backup_timestamp(){
  local database_name=${1:?"missing database name"}
  local database_literal
  database_literal=$(quote_tsql_literal "$database_name")
  local backup_time=$(${sql_cmd} -d msdb -Q "SET NOCOUNT ON;select TOP 1 backup_start_date from backupset where name=${database_literal} and type='D' order by backup_set_id desc" )
  if [[ "${backup_time}" == *"Msg "* ]]; then
    echo 0
  else
    echo $(date -d "${backup_time%.*}" +%s)
  fi
}


function get_last_backup_timestamp_from_full_backup() {
  backup_time=$(${sql_cmd} -d msdb -Q "SET NOCOUNT ON;select TOP 1 backup_finish_date from backupset where name !='master' and type='D' order by backup_set_id desc" )
  if [[ "${backup_time}" == *"Msg "* ]]; then
    echo 0
  else
    echo $(date -d "${backup_time%.*}" +%s)
  fi
}

function find_full_backup_path() {
  local database_name=${1:?"missing database name"}
  local order=${2:?"missing full backup order"}
  local paths_file path timestamp selected_path="" selected_timestamp=""
  case "$order" in
    newest|oldest) ;;
    *) return 1 ;;
  esac
  paths_file=$(mktemp /tmp/mssql-full-backups.XXXXXX) || return 1
  if ! datasafed_list_paths_to_file "$paths_file" -f --recursive /; then
    rm -f "$paths_file"
    return 1
  fi

  while IFS= read -r -d '' path; do
    [[ "$path" == */"${database_name}.full.bak.zst" ]] || continue
    [[ "$path" =~ ([0-9]{14}) ]] || continue
    timestamp=${BASH_REMATCH[1]}
    if [ -z "$selected_timestamp" ] \
      || { [ "$order" = newest ] && [[ "$timestamp" > "$selected_timestamp" ]]; } \
      || { [ "$order" = oldest ] && [[ "$timestamp" < "$selected_timestamp" ]]; }; then
      selected_timestamp=$timestamp
      selected_path=$path
    fi
  done < "$paths_file"
  rm -f "$paths_file"
  printf '%s' "$selected_path"
}

# The temporary list is read-only; removing it before an early return is not a
# concurrent write to the input stream.
# shellcheck disable=SC2094
function archive_has_pitr_basefull() {
  local database_name=${1:?"missing database name"}
  local paths_file path file_name timestamp
  paths_file=$(mktemp /tmp/mssql-pitr-basefull.XXXXXX) || return 1
  if ! datasafed_list_paths_to_file "$paths_file" -f --recursive "/${DP_BACKUP_NAME}"; then
    rm -f "$paths_file"
    return 1
  fi
  while IFS= read -r -d '' path; do
    file_name=${path##*/}
    if [[ "$file_name" == "${database_name}.basefull."*.bak.zst ]]; then
      timestamp=${file_name#"${database_name}.basefull."}
      timestamp=${timestamp%.bak.zst}
      if [[ "$timestamp" =~ ^[0-9]+$ ]]; then
        rm -f "$paths_file"
        return 0
      fi
    fi
  done < "$paths_file"
  rm -f "$paths_file"
  return 2
}

function backup_login_names() {
  ${sql_cmd} -Q "EXEC dbo.sp_help_revlogin" | datasafed push  - "server_login_names.sql"
}

# MSSQL log backup requires a base full backup
# https://learn.microsoft.com/zh-cn/sql/relational-databases/backup-restore/restore-a-sql-server-database-to-a-point-in-time-full-recovery-model?view=sql-server-ver17
function check_fullbackup_dir() {
  local database_name=${1:?"missing database name"}
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH%/*}"
  local latest_full_backup full_backup_in_pitr=false pitr_rc
  latest_full_backup=$(find_full_backup_path "$database_name" newest) || {
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
    return 1
  }
  if archive_has_pitr_basefull "$database_name"; then
    full_backup_in_pitr=true
  else
    pitr_rc=$?
    if [ "$pitr_rc" -ne 2 ]; then
      export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
      return 1
    fi
  fi

  # If the target database does not have a full backup and no full backup exists in PITR,
  # it means the database was created after PITR was enabled, and a full backup needs to be created in PITR
  if [ -z "${latest_full_backup}" ] && [ "$full_backup_in_pitr" = false ]; then
      DP_log "no full backup found for database ${database_name}"
      do_base_backup "${database_name}"
      export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
      return
  fi

  if [ -n "${latest_full_backup}" ]; then
    if [ ! -f "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info" ]; then
      # if ${database}.basefull.info doesn't exist, it's the first time log backup is enabled, just record the latest full backup path and timestamp
      init_basefull_info "${database_name}" "${latest_full_backup}"
    else
      # if ${database}.basefull.info already exists, it means log backup is in progress and the ${database}.basefull.info content needs to be updated with existing full backups
      update_basefull_info "${database_name}" "${latest_full_backup}"
    fi
  fi
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
}

function init_basefull_info() {
  local database_name=${1:?"missing database name"}
  local latest_full_backup=${2:?"missing latest full backup"}
  local full_backup_timestamp=$(get_full_backup_timestamp "${database_name}")
  if [[ ${full_backup_timestamp} -eq 0 ]]; then
    # try to get unix timestamp from latest full backup path
    local latest_full_backup_timestamp=$(dirname "${latest_full_backup}" | awk -F'-' '{print $NF}')
    full_backup_timestamp=$(date -d "${latest_full_backup_timestamp:0:4}-${latest_full_backup_timestamp:4:2}-${latest_full_backup_timestamp:6:2} ${latest_full_backup_timestamp:8:2}:${latest_full_backup_timestamp:10:2}:${latest_full_backup_timestamp:12:2}" +%s 2>/dev/null)
  fi

  mkdir -p "${BACKUP_DIR}/${DP_BACKUP_NAME}"
  archive_metadata_write_single_record \
    "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info" \
    "$latest_full_backup" "$full_backup_timestamp" "$NEXT_LOG_BACKUP_PLACEHOLDER"
}

function update_basefull_info() {
  local database_name=${1:?"missing database name"}
  local latest_full_backup=${2:?"missing latest full backup"}
  local metadata_file="${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info"
  local contains_rc
  mkdir -p "${BACKUP_DIR}/${DP_BACKUP_NAME}"
  # If the latest full backup information doesn't exist in info, add it
  if archive_metadata_contains_path "$metadata_file" "$latest_full_backup"; then
    :
  else
    contains_rc=$?
    [ "$contains_rc" -eq 2 ] || return 1
    local full_backup_timestamp=$(get_full_backup_timestamp "${database_name}")
    if [[ ${full_backup_timestamp} -eq 0 ]]; then
      # try to get unix timestamp from latest full backup path
      local latest_full_backup_timestamp=$(dirname "${latest_full_backup}" | awk -F'-' '{print $NF}')
      full_backup_timestamp=$(date -d "${latest_full_backup_timestamp:0:4}-${latest_full_backup_timestamp:4:2}-${latest_full_backup_timestamp:6:2} ${latest_full_backup_timestamp:8:2}:${latest_full_backup_timestamp:10:2}:${latest_full_backup_timestamp:12:2}" +%s 2>/dev/null)
    fi
    archive_metadata_append_record \
      "$metadata_file" "$latest_full_backup" "$full_backup_timestamp" "$NEXT_LOG_BACKUP_PLACEHOLDER"
  fi

  # Clean up records in XX.basefull.info that are older than the database oldest full backup
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH%/*}"
  local oldest_full_backup start_index=-1 index old_fullbackup_timestamp paths_file line file_name timestamp
  oldest_full_backup=$(find_full_backup_path "$database_name" oldest) || {
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
    return 1
  }
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
  archive_metadata_load_file "$metadata_file" || return 1
  for index in "${!ARCHIVE_METADATA_PATHS[@]}"; do
    if [ "${ARCHIVE_METADATA_PATHS[$index]}" = "$oldest_full_backup" ]; then
      start_index=$index
      break
    fi
  done
  if [ "$start_index" -gt 0 ]; then
    old_fullbackup_timestamp=${ARCHIVE_METADATA_FULL_TIMESTAMPS[$start_index]}
    archive_metadata_write_loaded_file "$metadata_file" "$start_index"
    DP_log "Cleaned up basefull.info for database ${database_name}."
    datasafed push - "${database_name}.basefull.info" < "$metadata_file"

    paths_file=$(mktemp /tmp/mssql-old-archive-files.XXXXXX) || return 1
    if ! datasafed_list_paths_to_file "$paths_file" -f "/${database_name}" -s mtime; then
      rm -f "$paths_file"
      return 1
    fi
    while IFS= read -r -d '' line; do
      file_name=${line##*/}
      if [[ "$file_name" =~ \.(basefull\.)?([0-9]+)\.bak\.zst$ ]]; then
        timestamp=${BASH_REMATCH[2]}
      else
        continue
      fi
      if [[ -n "${timestamp}" && "${timestamp}" -lt "${old_fullbackup_timestamp}" ]]; then
        DP_log "Deleting old backup file: ${line} (timestamp: ${timestamp})"
        datasafed rm "${line}"
      fi
    done < "$paths_file"
    rm -f "$paths_file"
  fi
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
}

function do_base_backup() {
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
    local database_name=${1:?"missing database name"}
    DP_log "Base full backup for database [${database_name}] not found. Creating one."
		local backup_file="${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.bak"
		mkdir -p "$(dirname "${backup_file}")"
    local backup_sql
    local database_sql backup_path_sql media_name_sql database_literal
    database_sql=$(quote_tsql_identifier "$database_name")
    backup_path_sql=$(quote_tsql_literal "$backup_file")
    media_name_sql=$(quote_tsql_literal "KB-${DP_BACKUP_NAME}")
    database_literal=$(quote_tsql_literal "$database_name")
    backup_sql=$(cat <<EOF
BACKUP DATABASE ${database_sql}
TO DISK = ${backup_path_sql}
   WITH FORMAT,
    COMPRESSION,
    MEDIANAME = ${media_name_sql},
    STATS=1,
    NAME = ${database_literal};
GO
EOF
)
		DP_log "Executing full backup: ${backup_sql}"
		set +e
		local result=$(${sql_cmd} -Q "${backup_sql}")
		set -e
		if [[ "$result" == *"Msg "* ]] || [[ ! -f "${backup_file}" ]]; then
			DP_log "Failed to create base full backup for [${database_name}]. SQL output: ${result}"
			return 1
		fi

    backup_time=$(get_full_backup_timestamp "${database_name}")
    if [[ ${backup_time} -eq 0 ]]; then
      DP_log "backup full backup for database ${database_name} failed."
    else
      DP_log "Base full backup for [${database_name}] created successfully."
  		DP_log "Pushing base full backup for [${database_name}] to storage."

      datasafed push -z zstd-fastest "${backup_file}" "${database_name}/${database_name}.basefull.${backup_time}.bak.zst"
      if [ $? -ne 0 ]; then
        cp "$backup_file" "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.${backup_time}.bak"
      fi
    fi

    mkdir -p "${BACKUP_DIR}/${DP_BACKUP_NAME}"
    archive_metadata_write_single_record \
      "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info" \
      "${DP_BACKUP_NAME}/${database_name}/${database_name}.basefull.${backup_time}.bak.zst" \
      "$backup_time" "$NEXT_LOG_BACKUP_PLACEHOLDER"
		DP_log "Base full backup for [${database_name}] created and pushed successfully."
		rm -f "${backup_file}"
}

function do_log_backup() {
  local database_name=${1:?"missing database name"}
  local backup_file="${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.log.bak"
  local database_sql backup_path_sql media_name_sql database_literal
  database_sql=$(quote_tsql_identifier "$database_name")
  backup_path_sql=$(quote_tsql_literal "$backup_file")
  media_name_sql=$(quote_tsql_literal "KB_LOG_BAK")
  database_literal=$(quote_tsql_literal "$database_name")
  backup_sql="BACKUP LOG ${database_sql} TO DISK = ${backup_path_sql} WITH FORMAT,COMPRESSION,MEDIANAME=${media_name_sql},STATS=1,NAME = ${database_literal}";
  DP_log "backup transaction log for database: ${database}"
  DP_log "${backup_sql}"
  set +e
  result=$(${sql_cmd} -Q "DBCC TRACEON (3226, -1);$backup_sql")
  set -e
  if [[ "$result" == *"Msg "* ]]; then
    DP_log "${result}"
    DP_log "backup transaction log for database ${database_name} failed, try with NO_TRUNCATE."
    backup_sql="BACKUP LOG ${database_sql} TO DISK = ${backup_path_sql} WITH NO_TRUNCATE,MEDIANAME=${media_name_sql},STATS=1,NAME = ${database_literal}"
    DP_log "${backup_sql}"
    set +e
    result=$(${sql_cmd} -Q "DBCC TRACEON (3226, -1);$backup_sql")
    set -e
    if [[ "$result" == *"Msg "* ]]; then
      DP_log "${result}"
      return 1
    fi
  fi
  return 0
}

function backup_database_log() {
  local database_name=${1:?"missing database name"}
  local backup_time_file="${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.kb"
  local currentUnix=$(date +%s)
  local backup_file last_index log_backup
  # backup interval is 10 minutes
  if [ -f "$backup_time_file" ]; then
    local last_backup_time=$(cat "$backup_time_file")
    if [ $((${last_backup_time}+${BACKUP_INTERVAL})) -gt ${currentUnix} ]; then
      return
    fi
  fi
  # do backup
  backup_login_names
  # check base full backup
  check_fullbackup_dir "${database_name}"
  if ! do_log_backup "${database_name}"; then
    DP_log "backup transaction log for database ${database_name} failed."
    return
  fi
  mkdir -p "${BACKUP_DIR}/${DP_BACKUP_NAME}"
  echo "$(date +%s)" > "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.kb"
  backup_time=$(get_log_backup_timestamp "${database_name}")
  backup_file="${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.log.bak"
  if [[ ${backup_time} -eq 0 ]]; then
    DP_log "backup transaction log for database ${database_name} failed."
  else
    # push must succeed before GLOBAL_END_TIME advances, otherwise the reported
    # restorable time range would cover a log backup that is not in the repo.
    # a push failure propagates through set -e so the controller can retry.
    datasafed push -z zstd-fastest "${backup_file}" "${database_name}/${database_name}.${backup_time}.bak.zst"
    if [ ${backup_time} -gt ${GLOBAL_END_TIME} ]; then
      GLOBAL_END_TIME=${backup_time}
    fi

    #  if the log backup corresponding to the latest full backup in info is NEXT_LOG_BACKUP_PLACEHOLDER, it means the current log backup corresponds to the full backup, and the log backup field for the latest full backup in info needs to be updated to the current log backup
    if [ -f "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info" ]; then
      archive_metadata_load_file "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info"
      last_index=$((${#ARCHIVE_METADATA_PATHS[@]} - 1))
      log_backup=${ARCHIVE_METADATA_NEXT_LOG_TIMESTAMPS[$last_index]}
      if [[ "${log_backup}" == "${NEXT_LOG_BACKUP_PLACEHOLDER}" ]]; then
          archive_metadata_set_last_next \
            "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info" "$backup_time"
          datasafed push - "${database_name}.basefull.info" \
            < "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.basefull.info"
      fi
    fi

  fi
  # clean the backup file in the disk
  if [ -f "${backup_file}"  ]; then
    rm -rf "$backup_file"
  fi
}


function backup_all_databases_log() {
  GLOBAL_END_TIME=0
  if ! load_database_names user-only; then
    DP_error_log "failed to enumerate database names; failing the archive backup action"
    return 1
  fi
  for database in "${DP_DATABASE_NAMES[@]}"; do
     backup_database_log "${database}"
  done
}

function check_mssql_process() {
  is_ok=false
  for ((i=1;i<4;i++));do
    value=$(${sql_cmd} -Q "SET NOCOUNT ON;select role_desc from sys.dm_hadr_availability_replica_states where is_local=1")
    if [[ "$value" == "PRIMARY" ]]; then
       is_ok=true
       break
    fi
    DP_error_log "target pod/${DP_TARGET_POD_NAME} is not PRIMARY, current role: ${value}, retry detection!"
    sleep 10
  done
  if [[ ${is_ok} == "false" ]];then
    DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not PRIMARY, current role: ${value}"
    exit 1
  fi
}

# clean up expired logfiles, interval is 60s
function purge_expired_files() {
  local currentUnix=$(date +%s)
  expiredUnix=$((${currentUnix}-${DP_TTL_SECONDS}))
  local paths_file file
  paths_file=$(mktemp /tmp/mssql-expired-archive-files.XXXXXX) || return 1
  if ! datasafed_list_paths_to_file "$paths_file" -f --recursive --older-than "$expiredUnix" /; then
    rm -f "$paths_file"
    return 1
  fi
  while IFS= read -r -d '' file; do
    if [[ $file == *"backup_meta.kb" ]]; then
      continue
    fi
    datasafed rm "$file"
    echo "$file"
  done < "$paths_file"
  rm -f "$paths_file"
}

function get_start_time() {
  local paths_file oldest_file="" file file_name
  if [[ "${IS_INIT_BACKUP}" == "true" ]]; then
    # get the start time from the latest full backup
    get_last_backup_timestamp_from_full_backup
    IS_INIT_BACKUP=false
    return
  fi
  paths_file=$(mktemp /tmp/mssql-archive-start.XXXXXX) || return 1
  if ! datasafed_list_paths_to_file "$paths_file" -f / --recursive -s mtime; then
    rm -f "$paths_file"
    return 1
  fi
  while IFS= read -r -d '' file; do
    file_name=${file##*/}
    [[ "$file_name" == *basefull* ]] && continue
    if [[ "$file_name" =~ \.([0-9]+)\.bak\.zst$ ]]; then
      oldest_file=${BASH_REMATCH[1]}
      break
    fi
  done < "$paths_file"
  rm -f "$paths_file"
  if [ -n "$oldest_file" ]; then
    echo "$oldest_file"
  fi
}

function save_backup_status() {
  if [ ${GLOBAL_END_TIME} -eq 0 ]; then
     return
  fi
  local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
  START_TIME=$(get_start_time)
  START_TIME=$(date -d @${START_TIME} -u "+%Y-%m-%dT%H:%M:%SZ")
  END_TIME=$(date -d @${GLOBAL_END_TIME} -u "+%Y-%m-%dT%H:%M:%SZ")
  DP_log "save backup status, TOTAL_SIZE: ${TOTAL_SIZE}, START_TIME: ${START_TIME}, END_TIME: ${END_TIME} "
  DP_save_backup_status_info "${TOTAL_SIZE}" "${START_TIME}" "${END_TIME}"
}

check_is_init_transaction_backup
while true; do
  check_mssql_process

  backup_all_databases_log

  # purge_expired_files

  save_backup_status

  sleep 5
done
