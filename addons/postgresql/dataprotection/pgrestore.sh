# shellcheck disable=SC2148
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}
function remote_file_exists() {
    local out=$(datasafed list $1)
    if [ "${out}" == "$1" ]; then
        echo "true"
        return
    fi
    echo "false"
}

# Construct pg_restore options string based on input parameters.
construct_pg_restore_options() {
  PG_RESTORE_OPTIONS=""

  # Include specific schemas (comma-separated list)
  if [ -n "${schemas}" ]; then
    for schema in ${schemas//,/ }; do
      PG_RESTORE_OPTIONS+=" --schema=${schema}"
    done
  fi
  # Exclude specific schemas (comma-separated list)
  if [ -n "${excludeSchemas}" ]; then
    for schema in ${excludeSchemas//,/ }; do
      PG_RESTORE_OPTIONS+=" --exclude-schema=${schema}"
    done
  fi
  # Include specific tables (comma-separated list)
  if [ -n "${tables}" ]; then
    for table in ${tables//,/ }; do
      PG_RESTORE_OPTIONS+=" --table=${table}"
    done
  fi
  # Exclude specific tables (comma-separated list)
  if [ -n "${excludeTables}" ]; then
    for table in ${excludeTables//,/ }; do
      PG_RESTORE_OPTIONS+=" --exclude-table=${table}"
    done
  fi

  # Format, the dafault is tar format
  if [ "${format}" = "p" ] || [ "${format}" = "plain" ]; then
    PG_RESTORE_OPTIONS+=" -Fp"
  else
    PG_RESTORE_OPTIONS+=" -Ft"
  fi
  if [ -n "${jobs}" ]; then
    # Run jobs in parallel
    PG_RESTORE_OPTIONS+=" --jobs=${jobs}"
  fi
  if [ -n "${setRole}" ]; then
    # role to set before excuting
    PG_RESTORE_OPTIONS+=" --role=${setRole}"
  fi
  if [ -n "${ignoreOwner}" ] && [ "${ignoreOwner}" = "true" ]; then
    # Ignore ownership information
    PG_RESTORE_OPTIONS+=" --no-owner"
  fi
  if [ -n "${dataOnly}" ] && [ "${dataOnly}" = "true" ]; then
    # Restore only the data
    PG_RESTORE_OPTIONS+=" --data-only"
  fi
  if [ -n "${schemaOnly}" ] && [ "${schemaOnly}" = "true" ]; then
    # Restore only the schema, no data
    PG_RESTORE_OPTIONS+=" --schema-only"
  fi
  if [ -z "${clean}" ] || [ "${clean}" = "true" ]; then
    # Clean database objects before restore
    PG_RESTORE_OPTIONS+=" --clean"
  fi
  if [ -z "${ifExists}" ] || [ "${ifExists}" = "true" ]; then
    # Use 'IF EXISTS' when dropping objects
    PG_RESTORE_OPTIONS+=" --if-exists"
  fi
  if [ -n "${noPrivileges}" ] && [ "${noPrivileges}" = "true" ]; then
    # Exclude privilege information
    PG_RESTORE_OPTIONS+=" --no-privileges"
  fi
  if [ -n "${disableTriggers}" ] && [ "${disableTriggers}" = "true" ]; then
    # Disable triggers during restore
    PG_RESTORE_OPTIONS+=" --disable-triggers"
  fi
  if [ -n "${noComments}" ] && [ "${noComments}" = "true" ]; then
    # Exclude comments
    PG_RESTORE_OPTIONS+=" --no-comments"
  fi
  if [ -n "${singleTransaction}" ] && [ "${singleTransaction}" = "true" ]; then
    # Restore as a single transaction
    PG_RESTORE_OPTIONS+=" --single-transaction"
  fi
  PG_RESTORE_OPTIONS+=" --verbose"
  echo "${PG_RESTORE_OPTIONS}"
}

# Construct a file name based on $format environment variable
file_name() {
  local prefix=${DP_BACKUP_NAME}
  if [ "${format}" = "p" ] || [ "${format}" = "plain" ]; then
    echo "${prefix}.sql"
  else
    echo "${prefix}.tar"
  fi
}

# Check if the given format is plain.
is_plain() {
  if [ "${format}" = "p" ] || [ "${format}" = "plain" ] ; then
      echo "true"
      return
  fi
  echo "false"
}

# Check if the backup exists
FILE_NAME=$(file_name)
if [ $(remote_file_exists ${FILE_NAME}.zst) == "false" ]; then
  exit 1
fi

if [ -z "${database}" ]; then
  echo "no database specified"
  exit 1
fi

if [ $(is_plain) == "true" ]; then
  datasafed pull -d zstd-fastest ${FILE_NAME}.zst - | psql -h ${DP_DB_HOST} -p ${DP_DB_PORT} -U ${DP_DB_USER}
else
  PG_RESTORE_OPTIONS="-d ${database}$(construct_pg_restore_options)"
  # print options
  echo "pg_restore options: ${PG_RESTORE_OPTIONS}"
  TMP_DIR=./tmp
  mkdir -p ${TMP_DIR}
  datasafed pull -d zstd-fastest ${FILE_NAME}.zst - > ${TMP_DIR}/${FILE_NAME}
  # pg_restore will fail if the database does not exist, so we create it by connecting to the default database "postgres"
  pg_restore -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_RESTORE_OPTIONS} ${TMP_DIR}/${FILE_NAME} 2> >(tee restore.log >&2) || {
    if grep -q "database \"${database}\" does not exist" restore.log; then
      echo "database \"${database}\" does not exist, create it"
      PG_RESTORE_OPTIONS="-d postgres$(construct_pg_restore_options) --create"
      echo "pg_restore options: ${PG_RESTORE_OPTIONS}"
      pg_restore -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_RESTORE_OPTIONS} ${TMP_DIR}/${FILE_NAME}
    else
      rm -rf ${TMP_DIR}
      echo "restore failed!"
      exit 1
    fi
  }
  rm -rf ${TMP_DIR}
fi
echo "restore complete!"