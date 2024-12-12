# shellcheck disable=SC2148
# pg_dump extracts a PostgreSQL database into a script file or other archive file
# more info: https://www.postgresql.org/docs/current/app-pgdump.html
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

# Construct pg_dump options string based on input parameters.
construct_pg_dump_options() {
  PG_DUMP_OPTIONS=""
  
  # schemas, comma-separated
  if [ -n "${schemas}" ]; then
    for schema in ${schemas//,/ }; do
      PG_DUMP_OPTIONS+=" --schema=${schema}"
    done
  fi
  # exclude schemas, comma-separated
  if [ -n "${excludeSchemas}" ]; then
    for schema in ${excludeSchemas//,/ }; do
      PG_DUMP_OPTIONS+=" --exclude-schema=${schema}"
    done
  fi
  # tables, comma-separated
  if [ -n "${tables}" ]; then
    for table in ${tables//,/ }; do
      PG_DUMP_OPTIONS+=" --table=${table}"
    done
  fi
  # exclude tables, comma-separated
  if [ -n "${excludeTables}" ]; then
    for table in ${excludeTables//,/ }; do
      PG_DUMP_OPTIONS+=" --exclude-table=${table}"
    done
  fi

    # Format, the dafault is tar format
  if [ "${format}" = "p" ] || [ "${format}" = "plain" ]; then
    PG_DUMP_OPTIONS+=" -Fp"
  else
    PG_DUMP_OPTIONS+=" -Ft"
  fi
  if [ -n "${dataOnly}" ] && [ "${dataOnly}" = "true" ]; then
    # boolean, whether to dump only data
    PG_DUMP_OPTIONS+=" --data-only"
  fi
  if [ -n "${schemaOnly}" ] && [ "${schemaOnly}" = "true" ]; then
    # boolean, whether to dump only schema
    PG_DUMP_OPTIONS+=" --schema-only"
  fi
  if [ -n "${jobs}" ]; then
    # number of jobs to run in parallel
    PG_DUMP_OPTIONS+=" --jobs=${jobs}"
  fi
  if [ -n "${setRole}" ]; then
    # role to set before excuting
    PG_DUMP_OPTIONS+=" --role=${setRole}"
  fi
  if [ -n "${disableTriggers}" ] && [ "${disableTriggers}" = "true" ]; then
    # boolean, whether to disable triggers
    PG_DUMP_OPTIONS+=" --disable-triggers"
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
  if [ -n "${encoding}" ] && [ "${encoding}" != "UTF-8" ]; then
    # encoding to use
    PG_DUMP_OPTIONS+=" --encoding=${encoding}"
  fi
  PG_DUMP_OPTIONS+=" --clean"
  PG_DUMP_OPTIONS+=" --if-exists"
  PG_DUMP_OPTIONS+=" --no-owner"
  PG_DUMP_OPTIONS+=" --no-privileges"
  PG_DUMP_OPTIONS+=" --verbose"
  echo "${PG_DUMP_OPTIONS}"
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

START_TIME=`get_current_time`

if [ -z "${database}" ]; then
  echo "no database specified"
  exit 1
fi

PG_DUMP_OPTIONS="-d ${database}$(construct_pg_dump_options)"
# print options
echo "pg_dump options: ${PG_DUMP_OPTIONS}"
pg_dump -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_DUMP_OPTIONS} | datasafed push -z zstd-fastest - "/$(file_name).zst"
# stat and save the backup information
stat_and_save_backup_info "$START_TIME"
echo "backup done!";