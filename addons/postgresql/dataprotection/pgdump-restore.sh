#!/bin/bash
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${POSTGRES_PASSWORD}
BACKUP_DIR=$BACKUP_DIR/${DP_BACKUP_NAME}
psql_cmd="psql -h ${DP_DB_HOST} -U ${POSTGRES_USER} -p ${DP_DB_PORT}"
mkdir -p $BACKUP_DIR
trap "[ -d $BACKUP_DIR ] && rm -rf $BACKUP_DIR" EXIT

datasafed pull "${DP_BACKUP_NAME}.tar" - | tar -xf - -C $BACKUP_DIR

# Set default values
if [ -z "$jobs" ]; then
  jobs=4
fi

# Build pg_dump parameters
# Roles are not dumped by pg_dump; the target cluster (e.g. a freshly
# restored one) usually does not have the roles referenced by ownership and
# ACL statements, so skip restoring owners and privileges altogether.
params="-j $jobs -Fd -v -C -d postgres --no-owner --no-privileges"
if [ -n "$database" ]; then
    $psql_cmd -d postgres -Atc "create database $database" || echo "Failed to create database $database"
fi

# Handle schema selection
if [ -n "$schemas" ]; then
  for schema in $(echo "$schemas" | tr ',' '\n'); do
     params="$params -n $schema"
     if [ -n "$database" ]; then
        $psql_cmd -d $database -Atc "create schema if not exists $schema" || echo "Failed to create schema $schema"
     fi
  done
fi

# Handle table selection
if [ -n "$tables" ]; then
  schemas_to_create=""
  for table in $(echo "$tables" | tr ',' '\n'); do
     params="$params -t $table"
     schema=$(echo "$table" | cut -d'.' -f1)
     if [ -n "$schema" ] && [ "$schema" != "$table" ]; then
       if ! echo "$schemas_to_create" | grep -v "^$schema$" > /dev/null 2>&1; then
         schemas_to_create="$schemas_to_create"$'\n'"$schema"
       fi
     fi
  done
  for schema in $(echo "$schemas_to_create" | grep -v '^$' | sort -u); do
    if [ -n "$database" ]; then
      $psql_cmd -d $database -Atc "create schema if not exists $schema" || echo "Failed to create schema $schema"
    fi
  done
fi

# Handle schema only
if [ "$schema_only" == "true" ]; then
  params="$params --schema-only"
fi

if [ "$conflict_policy" == "DROP" ]; then
  params="$params --clean --if-exists"
elif [ "$conflict_policy" == "FAIL" ]; then
  params="$params --exit-on-error"
else
  set +e
fi

echo "parameters: $params"

# Restore; capture the exit code explicitly instead of letting set -e abort,
# so the conflict policy can decide how ignored errors are reported.
# stderr goes through a synchronous tee (not an async process substitution),
# so /tmp/pg_restore.log is guaranteed complete before it is grepped below.
exec 3>&1
set +e
pg_restore -h ${DP_DB_HOST} -U ${POSTGRES_USER} -p ${DP_DB_PORT} ${params} $BACKUP_DIR 2>&1 1>&3 | tee /tmp/pg_restore.log >&2
exit_code=${PIPESTATUS[0]}
set -e
exec 3>&-
# Without --exit-on-error pg_restore continues past per-object errors and
# exits 1 with "errors ignored on restore". Only the non-FAIL policies may
# treat that as success, and only when every error is a benign conflict with
# the existing target database: objects already present ("already exists",
# "multiple primary keys"), or the database in use so its DROP fails. Data
# conflicts (duplicate key values), missing objects, and permission problems
# must fail.
if [ "$exit_code" -ne 0 ] && [ "$conflict_policy" != "FAIL" ] && [ -f /tmp/pg_restore.log ] \
    && grep -q "pg_restore: warning: errors ignored on restore" /tmp/pg_restore.log; then
  total_errors=$(grep -c "^pg_restore: error:" /tmp/pg_restore.log || true)
  existing_errors=$(grep "^pg_restore: error:" /tmp/pg_restore.log | grep -cE "already exists|multiple primary keys for table|is being accessed by other users" || true)
  if [ "$total_errors" -gt 0 ] && [ "$total_errors" = "$existing_errors" ]; then
    echo "pg_restore reported only pre-existing-object errors; treating as success under conflict_policy=${conflict_policy:-CONTINUE}"
    exit_code=0
  else
    echo "pg_restore reported non-conflict errors; failing restore" >&2
    grep "^pg_restore: error:" /tmp/pg_restore.log | grep -vE "already exists|multiple primary keys for table|is being accessed by other users" >&2 || true
  fi
fi
exit "$exit_code"
