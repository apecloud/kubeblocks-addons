#!/bin/bash
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}
BACKUP_DIR=$BACKUP_DIR/${DP_BACKUP_NAME}
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

# Handle schema selection
if [ -n "$schemas" ]; then
  for schema in $(echo "$schemas" | tr ',' '\n'); do
     params="$params -n $schema"
  done
fi

# Handle table selection
if [ -n "$tables" ]; then
  for table in $(echo "$tables" | tr ',' '\n'); do
     params="$params -t $table"
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

# Download and restore
pg_restore -h ${DP_DB_HOST} -U ${DP_DB_USER} -p ${DP_DB_PORT} ${params} $BACKUP_DIR 2> >(tee /tmp/pg_restore.log >&2)
exit_code=$?
if [ -f /tmp/pg_restore.log ] && grep "pg_restore: warning: errors ignored on restore" /tmp/pg_restore.log ; then
  exit_code=0
fi
exit $exit_code

