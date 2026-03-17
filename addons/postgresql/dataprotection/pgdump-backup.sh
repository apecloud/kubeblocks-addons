#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}
mkdir -p $BACKUP_DIR
BACKUP_DIR=$BACKUP_DIR/${DP_BACKUP_NAME}

function handle_exit_signal() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    if [ -d "$BACKUP_DIR" ]; then
      rm -rf "$BACKUP_DIR"
    fi
    exit 1
  fi
}

trap handle_exit_signal EXIT

START_TIME=$(get_current_time)

# Set default values
if [ -z "$jobs" ]; then
  jobs=4
fi

# Build pg_dump parameters
params="-j $jobs -Fd -f $BACKUP_DIR -Z lz4 -v"

# Handle database selection
if [ -n "$database" ]; then
  params="$params -d $database"
fi

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

echo "parameters: $params"

# Perform backup
pg_dump -h ${DP_DB_HOST} -U ${DP_DB_USER} -p ${DP_DB_PORT} ${params}

cd $BACKUP_DIR
tar -cf - . |  datasafed push - "/${DP_BACKUP_NAME}.tar"
# Stat and save backup information
stat_and_save_backup_info "$START_TIME"
