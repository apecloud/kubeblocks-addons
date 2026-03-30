#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT
if [ -z "$threads" ]; then
  threads=4
fi
params="--threads=$threads --triggers --routines"
if [ -n "$tables" ]; then
  params="$params -T $tables"
fi
if [ "$trx_tables" == "true" ]; then
  params="$params --trx-tables"
fi
if [ "${no_data}" == "true" ]; then
  params="${params} --no-data"
fi
if [ -n "$databases" ]; then
  params="${params} -B $databases"
fi

echo "parameters: $params"

mydumper -h ${DP_DB_HOST} -u ${DP_DB_USER} -p ${DP_DB_PASSWORD} -P ${DP_DB_PORT}  \
  --stream --build-empty-files --chunk-filesize 256 ${params} \
  2> >(tee /tmp/mydumper.log >&2) | datasafed push -z zstd-fastest - "/${DP_BACKUP_NAME}.mydumper.zst"

TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}"