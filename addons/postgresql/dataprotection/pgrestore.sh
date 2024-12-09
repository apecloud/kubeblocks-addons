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


  # Options for schemas and tables; these are mutually exclusive
  if [ -n "${schemas}" ]; then
    # Include specific schemas (comma-separated list)
    for schema in ${schemas//,/ }; do
      PG_RESTORE_OPTIONS+=" --schema=${schema}"
    done
  elif [ -n "${excludeSchemas}" ]; then
    # Exclude specific schemas (comma-separated list)
    for schema in ${excludeSchemas//,/ }; do
      PG_RESTORE_OPTIONS+=" --exclude-schema=${schema}"
    done
  elif [ -n "${tables}" ]; then
    # Include specific tables (comma-separated list)
    for table in ${tables//,/ }; do
      PG_RESTORE_OPTIONS+=" --table=${table}"
    done
  elif [ -n "${excludeTables}" ]; then
    # Exclude specific tables (comma-separated list)
    for table in ${excludeTables//,/ }; do
      PG_RESTORE_OPTIONS+=" --exclude-table=${table}"
    done
  fi

    # format
  if [ "${format}" = "c" ] || [ "${format}" = "custom" ]; then
    PG_RESTORE_OPTIONS+=" --format=c"
  elif [ "${format}" = "d" ] || [ "${format}" = "directory" ]; then
    PG_RESTORE_OPTIONS+=" --format=d"
  elif [ "${format}" = "t" ] || [ "${format}" = "tar" ]; then
    PG_RESTORE_OPTIONS+=" --format=t"
  else
    PG_RESTORE_OPTIONS+=" --format=p"
  fi
  if [ -n "${jobs}" ]; then
    # Run jobs in parallel
    PG_RESTORE_OPTIONS+=" --jobs=${jobs}"
  fi
  if [ -n "${compressLevel}" ] && [ "${compressLevel}" -ge 0 ] && [ "${compressLevel}" -le 9 ]; then
    # Set compression level (0-9)
    PG_RESTORE_OPTIONS+=" --compress=${compressLevel}"
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
  if [ -n "${clean}" ] && [ "${clean}" = "true" ]; then
    # Clean database objects before restore
    PG_RESTORE_OPTIONS+=" --clean"
  fi
  if [ -n "${create}" ] && [ "${create}" = "true" ]; then
    # Include CREATE DATABASE statement
    PG_RESTORE_OPTIONS+=" --create"
  fi
  if [ -n "${noPrivileges}" ] && [ "${noPrivileges}" = "true" ]; then
    # Exclude privilege information
    PG_RESTORE_OPTIONS+=" --no-privileges"
  fi
  if [ -n "${disableTriggers}" ] && [ "${disableTriggers}" = "true" ]; then
    # Disable triggers during restore
    PG_RESTORE_OPTIONS+=" --disable-triggers"
  fi
  if [ -n "${ifExists}" ] && [ "${ifExists}" = "true" ]; then
    # Use 'IF EXISTS' when dropping objects
    PG_RESTORE_OPTIONS+=" --if-exists"
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
  if [ "${format}" = "c" ] || [ "${format}" = "custom" ]; then
    echo "${prefix}.dump"
  elif [ "${format}" = "d" ] || [ "${format}" = "directory" ]; then
    echo "${prefix}"
  elif [ "${format}" = "t" ] || [ "${format}" = "tar" ]; then
    echo "${prefix}.tar"
  else
    echo "${prefix}.sql"
  fi
}

# Check if the given format is plain.
is_plain() {
  if [ "${format}" = "t" ] || [ "${format}" = "c" ] || [ "${format}" = "d" ] \
  || [ "${format}" = "tar" ] || [ "${format}" = "custom" ] || [ "${format}" = "directory" ]; then
      echo "false"
  fi
  echo "true"
}

if [ $(remote_file_exists $(file_name).zst) == "false" ]; then
  echo "backup ${DP_BACKUP_NAME} doesn't exist";
  exit 1
fi

# Set default database to 'postgres' if not provided; this is the default database name in PostgreSQL
# See https://www.postgresql.org/docs/current/static/runtime-config-connection.html#GUC-DATABASE
: "${database:=postgres}"

if [ $(is_plain) == "true" ]; then
  echo "excuting psql -h ${DP_DB_HOST} -p ${DP_DB_PORT} -U ${DP_DB_USER} -d ${database}"
  datasafed pull -d zstd-fastest $(file_name).zst - | psql -h ${DP_DB_HOST} -p ${DP_DB_PORT} -U ${DP_DB_USER} -d ${database}
else
  PG_RESTORE_OPTIONS="-d ${database}$(construct_pg_restore_options)"
  # print options
  echo "pg_restore options: ${PG_RESTORE_OPTIONS}";
  datasafed pull -d zstd-fastest $(file_name).zst - | pg_restore -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} -d ${database} ${PG_RESTORE_OPTIONS}
fi
echo "restore complete!";