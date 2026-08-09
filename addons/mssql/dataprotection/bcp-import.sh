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

if [ -z "$DP_DB_USER" ] && [ -n "$MSSQL_SA_USER" ]; then
  DP_DB_USER="$MSSQL_SA_USER"
  DP_DB_PASSWORD="$MSSQL_SA_PASSWORD"
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
IMPORT_DIR="${BACKUP_DIR}/BCP_IMPORT/${DP_BACKUP_NAME}"

handle_exit() {
  exit_code=$?
  if [ -d "${IMPORT_DIR}" ]; then
    rm -rf "${IMPORT_DIR}"
  fi
  if [ $exit_code -ne 0 ]; then
    DP_error_log "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

mkdir -p "${IMPORT_DIR}"

# Build table map from tables parameter (if specified)
declare -A TABLE_MAP
if [ -n "$tables" ]; then
  IFS=',' read -ra ENTRIES <<< "$tables"
  for entry in "${ENTRIES[@]}"; do
    entry=$(echo "$entry" | tr -d '[:space:]')
    TABLE_MAP["${entry}"]=1
  done
fi

# Step 1: download and extract DDL tar
DDL_DIR="${IMPORT_DIR}/ddl"
DP_log "downloading DDL tar"
datasafed pull "/ddl.tar.gz" "${IMPORT_DIR}/ddl.tar.gz" 2>/dev/null || true
if [ -f "${IMPORT_DIR}/ddl.tar.gz" ]; then
  tar xzf "${IMPORT_DIR}/ddl.tar.gz" -C "${IMPORT_DIR}"
  rm -f "${IMPORT_DIR}/ddl.tar.gz"
  DP_log "DDL extracted"
fi

# Step 2: download .dat files
DP_log "downloading data files from backup ${DP_BACKUP_NAME}"
for file in $(datasafed list / -r -f | grep '\.dat\.zst$'); do
  remote_path="${file}"
  file="${file#/}"
  local_rel_path="${file%.zst}"
  local_path="${IMPORT_DIR}/${local_rel_path}"

  # extract db.schema.table from db/schema_table.dat.zst
  f_db=$(echo "${file}" | cut -d'/' -f1)
  f_name=$(basename "${file}" .dat.zst)
  f_schema=$(echo "${f_name}" | cut -d'_' -f1)
  f_table=$(echo "${f_name}" | cut -d'_' -f2-)

  # filter by tables if specified
  if [ ${#TABLE_MAP[@]} -gt 0 ]; then
    key="${f_db}.${f_schema}.${f_table}"
    if [ -z "${TABLE_MAP[$key]}" ]; then
      DP_log "skip ${remote_path} (not in tables filter)"
      continue
    fi
  fi

  mkdir -p "$(dirname "${local_path}")"
  DP_log "download ${remote_path} to ${local_path}"
  datasafed pull -d zstd-fastest "${remote_path}" "${local_path}"
done

if [ -z "$batch_size" ]; then
  batch_size=10000
fi

# Step 3: create tables/views from DDL
if [ -d "${DDL_DIR}" ]; then
  for sql_file in $(find "${DDL_DIR}" -type f -name '*.sql' | sort); do
    rel_path="${sql_file#${DDL_DIR}/}"
    db=$(echo "${rel_path}" | cut -d'/' -f1)
    filename=$(basename "${sql_file}" .sql)
    schema=$(echo "${filename}" | cut -d'_' -f1)
    table=$(echo "${filename}" | cut -d'_' -f2-)

    # filter by tables map
    if [ ${#TABLE_MAP[@]} -gt 0 ]; then
      key="${db}.${schema}.${table}"
      if [ -z "${TABLE_MAP[$key]}" ]; then
        DP_log "skip DDL ${rel_path} (not in tables filter)"
        continue
      fi
    fi

    exists=$(${sql_cmd} -d "${db}" -Q "SET NOCOUNT ON;SELECT OBJECT_ID('${schema}.${table}')")
    exists=$(echo "$exists" | tr -d '[:space:]')
    if [ -n "${exists}" ] && [ "${exists}" != "NULL" ]; then
      DP_log "object ${db}.${schema}.${table} already exists, skip DDL"
      continue
    fi

    DP_log "creating ${db}.${schema}.${table} from ${rel_path}"
    ${sql_cmd} -d "${db}" -i "${sql_file}"
    if [ $? -ne 0 ]; then
      DP_error_log "create ${db}.${schema}.${table} from DDL failed"
    fi
  done
fi

# Step 4: import data
import_count=0
failed_count=0

for data_file in $(find "${IMPORT_DIR}" -type f -name '*.dat'); do
  rel_path="${data_file#${IMPORT_DIR}/}"
  db=$(echo "${rel_path}" | cut -d'/' -f1)
  filename=$(basename "${data_file}" .dat)
  schema=$(echo "${filename}" | cut -d'_' -f1)
  table=$(echo "${filename}" | cut -d'_' -f2-)

  DP_log "importing data into ${db}.${schema}.${table}"

  if [ "${clean_table}" == "true" ]; then
    obj_type=$(${sql_cmd} -d "${db}" -Q "SET NOCOUNT ON;SELECT type_desc FROM sys.objects WHERE object_id=OBJECT_ID('${schema}.${table}')")
    obj_type=$(echo "$obj_type" | tr -d '[:space:]')
    if [ "${obj_type}" != "VIEW" ]; then
      DP_log "truncating ${db}.${schema}.${table}"
      ${sql_cmd} -d "${db}" -Q "SET NOCOUNT ON;TRUNCATE TABLE ${schema}.${table}"
    fi
  fi

  $BCP "${db}.${schema}.${table}" IN "${data_file}" \
    -c -q -b ${batch_size} \
    -S "${DP_DB_HOST};TrustServerCertificate=Yes" -U ${DP_DB_USER} -P ${DP_DB_PASSWORD}

  if [ $? -ne 0 ]; then
    DP_error_log "import data ${db}.${schema}.${table} failed"
    failed_count=$(($failed_count + 1))
  else
    import_count=$(($import_count + 1))
  fi
done

DP_log "imported ${import_count} tables, failed ${failed_count} tables"

if [ ${import_count} -eq 0 ] && [ ${failed_count} -gt 0 ]; then
  DP_error_log "all imports failed"
  exit 1
fi
