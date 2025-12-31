# shellcheck disable=SC2148
# pg_restore restores a PostgreSQL database from an archive file created by pg_dump
# more info: https://www.postgresql.org/docs/current/app-pgrestore.html
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
  if [ -n "${dataOnly}" ] && [ "${dataOnly}" = "true" ]; then
    # Restore only the data
    PG_RESTORE_OPTIONS+=" --data-only"
  fi
  if [ -n "${schemaOnly}" ] && [ "${schemaOnly}" = "true" ]; then
    # Restore only the schema, no data
    PG_RESTORE_OPTIONS+=" --schema-only"
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
  PG_RESTORE_OPTIONS+=" --clean"
  PG_RESTORE_OPTIONS+=" --if-exists"
  PG_RESTORE_OPTIONS+=" --no-owner"
  PG_RESTORE_OPTIONS+=" --no-privileges"
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

# Create database if not exist
create_database_if_not_exist() {
  psql -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} -c "SELECT 1 FROM pg_database WHERE datname = '${database}';" | grep -q "1" || {
    echo "database ${database} does not exist, creating it..."
    psql -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} -c "CREATE DATABASE ${database} TEMPLATE template0;"
  }
}

# Check if the backup exists
FILE_NAME=$(file_name)
if [ $(remote_file_exists ${FILE_NAME}.zst) == "false" ]; then
  exit 1
fi

# Check if the dump.info exists
if [ $(remote_file_exists dump.info) == "false" ]; then
  echo "dump.info not found"
  exit 1
fi

# Get backup database name from dump.info
backup_database=$(datasafed pull dump.info - | awk '{print $2}')
echo "backup database: ${backup_database}"

# Get target database and create it if not exist
if [ -z "${database}" ]; then
  echo "no target database specified, use backup database name: ${backup_database}"
  database=${backup_database}
fi
echo "restore data into database: ${database}"
create_database_if_not_exist

if [ $(is_plain) == "true" ]; then
  # if backup file is plain, use psql to restore
  datasafed pull -d zstd-fastest ${FILE_NAME}.zst - | psql -h ${DP_DB_HOST} -p ${DP_DB_PORT} -U ${DP_DB_USER} -d ${database}
else
  # if backup file is tar, use pg_restore to restore

  # print options
  PG_RESTORE_OPTIONS="-d ${database}$(construct_pg_restore_options)"
  echo "pg_restore options: ${PG_RESTORE_OPTIONS}"
  if [ "${backup_database}" != "postgres" ]; then
    datasafed pull -d zstd-fastest ${FILE_NAME}.zst - | pg_restore -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_RESTORE_OPTIONS}
  else
    # FIXME:using pipe to restore "postgres" database leads to exit code 141 meaning pipefail
    # use temp dir to avoid this
    TMP_DIR=./tmp
    mkdir -p ${TMP_DIR}
    datasafed pull -d zstd-fastest ${FILE_NAME}.zst - > ${TMP_DIR}/${FILE_NAME}
    pg_restore -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_RESTORE_OPTIONS} ${TMP_DIR}/${FILE_NAME}
    rm -rf ${TMP_DIR}
  fi
fi
echo "restore complete!"