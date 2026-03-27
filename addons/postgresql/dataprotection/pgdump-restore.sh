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
# Set default values
if [ -z "$jobs" ]; then
  jobs=4
fi

# Build pg_dump parameters
params="-j $jobs -Fd -v -C -d postgres"
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
  params="$params --no-owner --no-privileges"
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
  if [ -z "$schemas" ]; then
    params="$params --no-owner --no-privileges"
  fi
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

# Download and restore
pg_restore -h ${DP_DB_HOST} -U ${POSTGRES_USER} -p ${DP_DB_PORT} ${params} $BACKUP_DIR 2> >(tee /tmp/pg_restore.log >&2)=
exit_code=$?
if [ -f /tmp/pg_restore.log ] && grep "pg_restore: warning: errors ignored on restore" /tmp/pg_restore.log ; then
  exit_code=0
fi
exit $exit_code

