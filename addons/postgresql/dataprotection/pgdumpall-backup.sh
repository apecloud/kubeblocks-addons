set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

# Construct pg_dump options string based on input parameters.
construct_pg_dumpall_options() {
  PG_DUMPALL_OPTIONS=""

  # General options
  if [ -n "${lockWaitTimeout}" ]; then
    PG_DUMPALL_OPTIONS+=" --lock-wait-timeout=${lockWaitTimeout}"
  fi

  # Options controlling the output content
  if [ -n "${dataOnly}" ] && [ "${dataOnly}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --data-only"
  fi
  if [ -n "${schemaOnly}" ] && [ "${schemaOnly}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --schema-only"
  fi
  if [ -n "${clean}" ] && [ "${clean}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --clean"
  fi
  if [ -n "${encoding}" ]; then
    PG_DUMPALL_OPTIONS+=" --encoding=${encoding}"
  fi
  if [ -n "${globalsOnly}" ] && [ "${globalsOnly}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --globals-only"
  fi
  if [ -n "${noOwner}" ] && [ "${noOwner}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-owner"
  fi
  if [ -n "${rolesOnly}" ] && [ "${rolesOnly}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --roles-only"
  fi
  if [ -n "${superuser}" ]; then
    PG_DUMPALL_OPTIONS+=" --superuser=${superuser}"
  fi
  if [ -n "${tablespacesOnly}" ] && [ "${tablespacesOnly}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --tablespaces-only"
  fi
  if [ -n "${noPrivileges}" ] && [ "${noPrivileges}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-privileges"
  fi

  # Additional options
  if [ -n "${binaryUpgrade}" ] && [ "${binaryUpgrade}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --binary-upgrade"
  fi
  if [ -n "${columnInserts}" ] && [ "${columnInserts}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --column-inserts"
  fi
  if [ -n "${disableDollarQuoting}" ] && [ "${disableDollarQuoting}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --disable-dollar-quoting"
  fi
  if [ -n "${disableTriggers}" ] && [ "${disableTriggers}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --disable-triggers"
  fi
  if [ -n "${excludeDatabase}" ]; then
    for db in ${excludeDatabase//,/ }; do
      PG_DUMPALL_OPTIONS+=" --exclude-database=${db}"
    done
  fi
  if [ -n "${extraFloatDigits}" ]; then
    PG_DUMPALL_OPTIONS+=" --extra-float-digits=${extraFloatDigits}"
  fi
  if [ -n "${ifExists}" ] && [ "${ifExists}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --if-exists"
  fi
  if [ -n "${inserts}" ] && [ "${inserts}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --inserts"
  fi
  if [ -n "${loadViaPartitionRoot}" ] && [ "${loadViaPartitionRoot}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --load-via-partition-root"
  fi
  if [ -n "${noComments}" ] && [ "${noComments}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-comments"
  fi
  if [ -n "${noPublications}" ] && [ "${noPublications}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-publications"
  fi
  if [ -n "${noRolePasswords}" ] && [ "${noRolePasswords}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-role-passwords"
  fi
  if [ -n "${noSecurityLabels}" ] && [ "${noSecurityLabels}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-security-labels"
  fi
  if [ -n "${noSubscriptions}" ] && [ "${noSubscriptions}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-subscriptions"
  fi
  if [ -n "${noSync}" ] && [ "${noSync}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-sync"
  fi
    if [ -n "${noTableAccessMethod}" ] && [ "${noTableAccessMethod}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-table-access-method"
  fi
  if [ -n "${noTablespaces}" ] && [ "${noTablespaces}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-tablespaces"
  fi
  if [ -n "${noToastCompression}" ] && [ "${noToastCompression}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-toast-compression"
  fi
  if [ -n "${noUnloggedTableData}" ] && [ "${noUnloggedTableData}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --no-unlogged-table-data"
  fi
  if [ -n "${onConflictDoNothing}" ] && [ "${onConflictDoNothing}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --on-conflict-do-nothing"
  fi
  if [ -n "${quoteAllIdentifiers}" ] && [ "${quoteAllIdentifiers}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --quote-all-identifiers"
  fi
  if [ -n "${rowsPerInsert}" ]; then
    PG_DUMPALL_OPTIONS+=" --rows-per-insert=${rowsPerInsert}"
  fi
  if [ -n "${useSetSessionAuthorization}" ] && [ "${useSetSessionAuthorization}" = "true" ]; then
    PG_DUMPALL_OPTIONS+=" --use-set-session-authorization"
  fi

  # Connection options
  if [ -n "${dbname}" ]; then
    PG_DUMPALL_OPTIONS+=" --dbname=${dbname}"
  fi
  if [ -n "${database}" ]; then
    PG_DUMPALL_OPTIONS+=" --database=${database}"
  fi
  if [ -n "${role}" ]; then
    PG_DUMPALL_OPTIONS+=" --role=${role}"
  fi
  PG_DUMPALL_OPTIONS+=" --verbose"
  echo "${PG_DUMPALL_OPTIONS}"
}

START_TIME=`get_current_time`
PG_DUMPALL_OPTIONS=$(construct_pg_dumpall_options)
pg_dumpall -U ${DP_DB_USER} -h ${DP_DB_HOST} -p ${DP_DB_PORT} ${PG_DUMPALL_OPTIONS} | datasafed push -z zstd-fastest - "/${DP_BACKUP_NAME}.zst"
# stat and save the backup information
stat_and_save_backup_info "$START_TIME"
echo "backup done!";