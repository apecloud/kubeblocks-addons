# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

set -e
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function need_full_backup() {
  local database_name=${1:?"missing database name"}
  local database_literal
  database_literal=$(quote_tsql_literal "$database_name")
  sql="SET NOCOUNT ON; select database_name from backupmediaset as m join backupset as b on b.media_set_id = m.media_set_id where b.database_name = ${database_literal} and type='D' and m.name like 'KB-%'"
  result=$(${sql_cmd} -d msdb -Q "${sql}")
  if [[ -z "${result}" ]]; then
    return 0
  else
    return 1
  fi
}

function backup_database() {
  local database_name=${1:?"missing database name"}
  local database_sql backup_path_sql media_name_sql database_literal
  database_sql=$(quote_tsql_identifier "$database_name")
  backup_path_sql=$(quote_tsql_literal "${BACKUP_DIR}/${DP_BACKUP_NAME}/${database_name}.incremental.bak")
  media_name_sql=$(quote_tsql_literal "KB-${DP_BACKUP_NAME}")
  database_literal=$(quote_tsql_literal "$database_name")
  backup_sql=$(cat <<EOF
BACKUP DATABASE ${database_sql}
TO DISK = ${backup_path_sql}
   WITH DIFFERENTIAL,
    FORMAT,
    COMPRESSION,
    MEDIANAME = ${media_name_sql},
    STATS=1,
    NAME = ${database_literal};
GO
EOF
)
  DP_log "execute ${backup_sql}"
  local result rc
  result=$($SQLCMD -S "${DP_DB_HOST}" -U "$DP_DB_USER" -P "$DP_DB_PASSWORD" -C -x -Q "$backup_sql")
  rc=$?
  # No differential base yet -> fall back to a full backup and propagate its rc.
  if [[ "$result" == *"current database backup does not exist"* ]]; then
    DP_error_log "differential backup database ${database_name} failed, perform a full backup."
    backup_database_with_full "${database_name}"
    return $?
  fi
  # Treat a non-zero sqlcmd exit or a T-SQL error message as a failure. (The
  # previous `return $?` returned the result of the last [[ ]] test, so a
  # successful differential wrongly returned 1.)
  if [ $rc -ne 0 ] || [[ "$result" == *"Msg "* ]]; then
    DP_error_log "${result}"
    return 1
  fi
  return 0
}


# create backup directory
if [[ ! -d "${BACKUP_DIR}/${DP_BACKUP_NAME}" ]]; then
  mkdir -p "${BACKUP_DIR}/${DP_BACKUP_NAME}"
fi

# do backup sql
# with options:
# if specify MEDIANAME, the all backups must be COMPRESSED or UNCOMPRESSED.
# MEDIANAME: an id to manager the backups
# NAME: backup set name in the media
# METADATA_ONLY: equals to SNAPSHOT
# NOINIT/INIT: by default is MOINIT, append your backups. INIT: overwrite the backups with same meida, retain media header.
# FORMAT: init the medias and all backupsets will invalid in the medis, be carefully to use it. By default is NOFORMAT.
# Fail-fast: any single database backup failure fails the whole action, so an
# incomplete backup is never reported as successful. master always takes a full
# backup; other databases take a differential when a full base already exists.
if ! load_database_names include-master; then
  DP_error_log "failed to enumerate database names; failing the backup action"
  exit 1
fi
for database in "${DP_DATABASE_NAMES[@]}"; do
   DP_log "start to backup database ${database}"
   if [ "${database}" == "master" ] || need_full_backup "${database}"; then
     backup_fn=backup_database_with_full
   else
     backup_fn=backup_database
   fi
   if ! "${backup_fn}" "${database}"; then
     DP_error_log "backup database ${database} failed; failing the backup action"
     exit 1
   fi
done
# push backup
push_backups
save_backup_status
