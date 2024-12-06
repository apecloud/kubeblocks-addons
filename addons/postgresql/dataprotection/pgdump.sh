# shellcheck disable=SC2148
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

# Construct pg_dump options string based on input parameters.
construct_pg_dump_options() {
  PG_DUMP_OPTIONS=""
  if [ -n "${database}" ]; then
    # database name to dump
    PG_DUMP_OPTIONS+=" -d=${database}"
  fi
  
  # Add options for schemas and tables; these are mutually exclusive
  if [ -n "${schemas}" ]; then
    # comma-separated list of schemas to include
    for schema in ${schemas//,/ }; do
      PG_DUMP_OPTIONS+=" --schema=${schema}"
    done
  elif [ -n "${excludeSchemas}" ]; then
    # comma-separated list of schemas to exclude
    for schema in ${excludeSchemas//,/ }; do
      PG_DUMP_OPTIONS+=" --exclude-schema=${schema}"
    done
  elif [ -n "${tables}" ]; then
    # comma-separated list of tables to include
    for table in ${tables//,/ }; do
      PG_DUMP_OPTIONS+=" --table=${table}"
    done
  elif [ -n "${excludeTables}" ]; then
    # comma-separated list of tables to exclude
    for table in ${excludeTables//,/ }; do
      PG_DUMP_OPTIONS+=" --exclude-table=${table}"
    done
  fi

  if [ -n "${dataOnly}" ] && [ "${dataOnly}" = "true" ]; then
    # boolean, whether to dump only data
    PG_DUMP_OPTIONS+=" --data-only"
  fi
  if [ -n "${schemaOnly}" ] && [ "${schemaOnly}" = "true" ]; then
    # boolean, whether to dump only schema
    PG_DUMP_OPTIONS+=" --schema-only"
  fi
  if [ -n "${clean}" ] && [ "${clean}" = "true" ]; then
    # boolean, whether to clean database objects
    PG_DUMP_OPTIONS+=" --clean"
  fi
  if [ -n "${create}" ] && [ "${create}" = "true" ]; then
    # boolean, whether to include CREATE DATABASE statement
    PG_DUMP_OPTIONS+=" --create"
  fi
  if [ -n "${jobs}" ]; then
    # number of jobs to run in parallel
    PG_DUMP_OPTIONS+=" --jobs=${jobs}"
  fi
  if [ -n "${compressLevel}" ] && [ "${compressLevel}" -ge 0 ] && [ "${compressLevel}" -le 9 ]; then
    # compression level (0-9)
    PG_DUMP_OPTIONS+=" --compress=${compressLevel}"
  fi
  if [ -n "${setRole}" ]; then
    # role to set before excuting
    PG_DUMP_OPTIONS+=" --role=${setRole}"
  fi
  if [ -n "${ignoreOwner}" ] && [ "${ignoreOwner}" = "true" ]; then
    # boolean, whether to ignore ownership
    PG_DUMP_OPTIONS+=" --no-owner"
  fi
  if [ -n "${noPrivileges}" ] && [ "${noPrivileges}" = "true" ]; then
    # boolean, whether to exclude privileges
    PG_DUMP_OPTIONS+=" --no-privileges"
  fi
  if [ -n "${disableTriggers}" ] && [ "${disableTriggers}" = "true" ]; then
    # boolean, whether to disable triggers
    PG_DUMP_OPTIONS+=" --disable-triggers"
  fi
  if [ -n "${ifExists}" ] && [ "${ifExists}" = "true" ]; then
    # boolean, whether to include 'IF EXISTS'
    PG_DUMP_OPTIONS+=" --if-exists"
  fi
  if [ -n "${useInserts}" ] && [ "${useInserts}" = "true" ]; then
    # boolean, whether to use INSERT statements
    PG_DUMP_OPTIONS+=" --inserts"
  fi
  if [ -n "${columnInserts}" ] && [ "${columnInserts}" = "true" ]; then
    # boolean, whether to use column names in INSERT statements
    PG_DUMP_OPTIONS+=" --column-inserts"
  fi
  if [ -n "${onConflictDoNothing}" ] && [ "${onConflictDoNothing}" = "true" ]; then
    # boolean, whether to use ON CONFLICT DO NOTHING
    PG_DUMP_OPTIONS+=" --on-conflict-do-nothing"
  fi
  if [ -n "${loadViaPartitionRoot}" ] && [ "${loadViaPartitionRoot}" = "true" ]; then
    # boolean, whether to load via partition root
    PG_DUMP_OPTIONS+=" --load-via-partition-root"
  fi
  if [ -n "${noComments}" ] && [ "${noComments}" = "true" ]; then
    # boolean, whether to exclude comments
    PG_DUMP_OPTIONS+=" --no-comments"
  fi
  if [ -n "${noTablespaces}" ] && [ "${noTablespaces}" = "true" ]; then
    # boolean, whether to exclude tablespaces
    PG_DUMP_OPTIONS+=" --no-tablespaces"
  fi
  if [ -n "${noUnloggedTableData}" ] && [ "${noUnloggedTableData}" = "true" ]; then
    # boolean, whether to exclude unlogged table data
    PG_DUMP_OPTIONS+=" --no-unlogged-table-data"
  fi
  if [ -n "${noBlobs}" ] && [ "${noBlobs}" = "true" ]; then
    # boolean, whether to exclude blobs
    PG_DUMP_OPTIONS+=" --no-blobs"
  fi
  PG_DUMP_OPTIONS+=" --verbose"
  echo "${PG_DUMP_OPTIONS}"
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


START_TIME=`get_current_time`
PG_DUMP_OPTIONS=$(construct_pg_dump_options)
pg_dump -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_DUMP_OPTIONS} | datasafed push - "/$(file_name)"
# stat and save the backup information
stat_and_save_backup_info "$START_TIME"
echo "backup done!";