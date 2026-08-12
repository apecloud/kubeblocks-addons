# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

# Auto-detect bcp path
if [ -f /opt/mssql-tools18/bin/bcp ]; then
  BCP=/opt/mssql-tools18/bin/bcp
elif [ -f /opt/mssql-tools/bin/bcp ]; then
  BCP=/opt/mssql-tools/bin/bcp
else
  BCP=bcp
fi

# Auto-detect sqlcmd path
if [ -f /opt/mssql-tools18/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools18/bin/sqlcmd
elif [ -f /opt/mssql-tools/bin/sqlcmd ]; then
  SQLCMD=/opt/mssql-tools/bin/sqlcmd
else
  SQLCMD=sqlcmd
fi

sql_cmd="$SQLCMD -S ${DP_DB_HOST} -U $DP_DB_USER -P $DP_DB_PASSWORD -C -h-1 -W"

trap handle_exit EXIT

DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}

DP_error_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} ERROR: $msg"
}

BACKUP_DIR=${BACKUP_DIR:-/var/opt/mssql/backup}
EXPORT_DIR="${BACKUP_DIR}/${DP_BACKUP_NAME}"
DDL_DIR="${EXPORT_DIR}/ddl"

handle_exit() {
  exit_code=$?
  if [ -d "${EXPORT_DIR}" ]; then
    rm -rf "${EXPORT_DIR}"
  fi
  if [ $exit_code -ne 0 ]; then
    DP_error_log "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

mkdir -p "${DDL_DIR}"

if [ -z "$format" ]; then
  format="char"
fi

if [ "$format" == "native" ]; then
  bcp_fmt="-n"
else
  bcp_fmt="-c"
fi

# Parse tables parameter: db.schema.table|view, comma separated
IFS=',' read -ra ENTRIES <<< "$tables"

DP_log "tables to export: ${tables}"

export_count=0
failed_count=0

for entry in "${ENTRIES[@]}"; do
  entry=$(echo "$entry" | tr -d '[:space:]')
  IFS='.' read -ra parts <<< "$entry"
  if [ "${#parts[@]}" -lt 3 ]; then
    DP_error_log "invalid table format: ${entry}, expected db.schema.table"
    failed_count=$(($failed_count + 1))
    continue
  fi
  db="${parts[0]}"
  schema="${parts[1]}"
  table="${parts[2]}"
  for ((i=3; i<${#parts[@]}; i++)); do
    table="${table}.${parts[$i]}"
  done

  data_file="${EXPORT_DIR}/${db}/${schema}_${table}.dat"
  ddl_file="${DDL_DIR}/${db}/${schema}_${table}.sql"
  mkdir -p "$(dirname "${ddl_file}")" "$(dirname "${data_file}")"

  # detect object type
  obj_type=$(${sql_cmd} -d "${db}" -Q "SET NOCOUNT ON;SELECT type_desc FROM sys.objects WHERE object_id=OBJECT_ID('${schema}.${table}')")
  obj_type=$(echo "$obj_type" | tr -d '[:space:]')
  DP_log "${db}.${schema}.${table} type: ${obj_type}"

  # export DDL
  if [ "${obj_type}" == "VIEW" ]; then
    ${sql_cmd} -d "${db}" -Q "SET NOCOUNT ON;SELECT OBJECT_DEFINITION(OBJECT_ID('${schema}.${table}'))" > "${ddl_file}"
    if [ $? -ne 0 ] || [ ! -s "${ddl_file}" ]; then
      DP_error_log "export DDL for view ${db}.${schema}.${table} failed"
      failed_count=$(($failed_count + 1))
      continue
    fi
    export_count=$(($export_count + 1))
  else
    # TABLE or unknown: export DDL and data
    ${sql_cmd} -d "${db}" -Q "SET NOCOUNT ON;
DECLARE @schema SYSNAME = '${schema}';
DECLARE @tbl SYSNAME = '${table}';
DECLARE @obj_id INT = OBJECT_ID(QUOTENAME(@schema) + '.' + QUOTENAME(@tbl));
DECLARE @sql NVARCHAR(MAX) = '';
DECLARE @pk_cols NVARCHAR(MAX) = '';

-- columns
SELECT @sql = @sql + '    ' + QUOTENAME(c.name) + ' ' +
    CASE WHEN c.is_computed = 1 THEN 'AS ' + cc.definition
    ELSE UPPER(t.name) +
        CASE
            WHEN t.name IN ('char','varchar','nchar','nvarchar','binary','varbinary') AND c.max_length = -1 THEN '(max)'
            WHEN t.name IN ('char','varchar','nchar','nvarchar','binary','varbinary') THEN '(' + CAST(CASE WHEN t.name IN ('nchar','nvarchar') THEN c.max_length/2 ELSE c.max_length END AS VARCHAR(10)) + ')'
            WHEN t.name IN ('decimal','numeric') THEN '(' + CAST(c.precision AS VARCHAR(10)) + ',' + CAST(c.scale AS VARCHAR(10)) + ')'
            WHEN t.name IN ('datetime2','datetimeoffset','time') AND c.scale <> 7 THEN '(' + CAST(c.scale AS VARCHAR(10)) + ')'
            WHEN t.name = 'float' AND c.precision <> 53 THEN '(' + CAST(c.precision AS VARCHAR(10)) + ')'
            ELSE ''
        END
    END +
    CASE WHEN c.is_identity = 1 THEN ' IDENTITY' ELSE '' END +
    CASE WHEN c.is_nullable = 0 AND c.is_computed = 0 THEN ' NOT NULL' ELSE ' NULL' END + ',' + CHAR(13)
FROM sys.columns c
JOIN sys.types t ON c.user_type_id = t.user_type_id
LEFT JOIN sys.computed_columns cc ON c.object_id = cc.object_id AND c.column_id = cc.column_id
WHERE c.object_id = @obj_id
ORDER BY c.column_id;

-- primary key
SELECT @pk_cols = @pk_cols + QUOTENAME(c.name) + ', '
FROM sys.indexes i
JOIN sys.index_columns ic ON i.object_id = ic.object_id AND i.index_id = ic.index_id
JOIN sys.columns c ON ic.object_id = c.object_id AND ic.column_id = c.column_id
WHERE i.object_id = @obj_id AND i.is_primary_key = 1
ORDER BY ic.key_ordinal;

IF @pk_cols <> '' SET @sql = @sql + '    PRIMARY KEY (' + LEFT(@pk_cols, LEN(@pk_cols)-1) + '),' + CHAR(13);

IF @sql <> ''
    SET @sql = 'CREATE TABLE ' + QUOTENAME(@schema) + '.' + QUOTENAME(@tbl) + '(' + CHAR(13) + LEFT(@sql, LEN(@sql)-2) + CHAR(13) + ')';
ELSE
    SET @sql = 'CREATE TABLE ' + QUOTENAME(@schema) + '.' + QUOTENAME(@tbl) + '()';
PRINT @sql;" > "${ddl_file}"

    if [ $? -ne 0 ] || [ ! -s "${ddl_file}" ]; then
      DP_error_log "export DDL for table ${db}.${schema}.${table} failed"
      failed_count=$(($failed_count + 1))
      continue
    fi

    # export data via bcp
    DP_log "exporting data of ${db}.${schema}.${table}"
    $BCP "${db}.${schema}.${table}" OUT "${data_file}" \
      ${bcp_fmt} -q \
      -S "${DP_DB_HOST};TrustServerCertificate=Yes" -U ${DP_DB_USER} -P ${DP_DB_PASSWORD}

    if [ $? -ne 0 ]; then
      DP_error_log "export data ${db}.${schema}.${table} failed"
      failed_count=$(($failed_count + 1))
    else
      DP_log "push data: ${db}/${schema}_${table}.dat"
      datasafed push -z zstd-fastest "${data_file}" "/${db}/${schema}_${table}.dat.zst"
      rm -f "${data_file}"
      export_count=$(($export_count + 1))
    fi
  fi
done

# tar and push DDL files
if [ "$(find "${DDL_DIR}" -type f | wc -l)" -gt 0 ]; then
  DP_log "packing DDL files"
  cd "${EXPORT_DIR}"
  tar czf ddl.tar.gz ddl/
  datasafed push "ddl.tar.gz" "/ddl.tar.gz"
  rm -rf "${DDL_DIR}" ddl.tar.gz
fi

DP_log "exported ${export_count} objects, failed ${failed_count}"

if [ ${export_count} -eq 0 ] && [ ${failed_count} -gt 0 ]; then
  DP_error_log "all exports failed"
  exit 1
fi

TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}"
DP_log "backup completed, total size: ${TOTAL_SIZE}"
