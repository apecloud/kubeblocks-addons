set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
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
  if [ -n "${database}" ]; then
    # Specify the database name to restore
    PG_RESTORE_OPTIONS+=" -d=${database}"
  fi

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

  if [ -n "${jobs}" ]; then
    # Run jobs in parallel
    PG_RESTORE_OPTIONS+=" --jobs=${jobs}"
  fi
  if [ -n "${compressLevel}" ]; then
    # Set compression level (0-9)
    PG_RESTORE_OPTIONS+=" --compress=${compressLevel}"
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

# Construct a file name based on a given prefix and $format environment variable
file_name() {
  local prefix=${DP_BACKUP_NAME}
  if [ "${format}" = "c" ]; then
    echo "${prefix}.dump"
  elif [ "${format}" = "d" ]; then
    echo "${prefix}/"
  elif [ "${format}" = "t" ]; then
    echo "${prefix}.tar"
  elif [ "${format}" = "p" ]; then
    echo "${prefix}.sql"
  else
    echo "${prefix}.sql"
  fi
}

# Check if the given format is plain.
is_plain() {
  if [ "${format}" = "c" ] || [ "${format}" = "d" ] || [ "${format}" = "t" ]; then
      echo "false"
  fi
  echo "true"
}

if [ $(remote_file_exists $(file_name)) == "true" ]; then
  datasafed pull $(file_name)
  echo "done!";
  exit 0
fi

if [ $(is_plain) == "true" ]; then
  psql -h ${DP_DB_HOST} -U ${DP_DB_USER} -d ${database} -f $(file_name)
else
  pg_restore -U ${DP_DB_USER} -h ${DP_DB_HOST} ${PG_RESTORE_OPTIONS} $(file_name);
fi
echo "restore complete!";