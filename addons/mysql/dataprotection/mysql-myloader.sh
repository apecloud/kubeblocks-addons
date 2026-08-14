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
case "${threads}" in
  "" | 0* | *[!0-9]*)
    echo "threads must be a positive integer" >&2
    exit 2
    ;;
esac
params="--threads=$threads"
if [ -n "${tables}" ]; then
  params="${params} -T ${tables}"
fi
# DROP, FAIL(default), NONE, TRUNCATE and DELETE
case "${drop_table}" in
  "") ;;
  DROP | FAIL | NONE | TRUNCATE | DELETE) params="${params} -o $drop_table" ;;
  *)
    echo "drop_table must be one of DROP, FAIL, NONE, TRUNCATE, DELETE" >&2
    exit 2
    ;;
esac
if [ "${no_data}" == "true" ]; then
  params="${params} --no-data"
fi
#if [ -n "$databases" ]; then
#  params="${params} -s $databases"
#fi

echo "parameters: $params"

datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.mydumper.zst" - | myloader --stream  \
  -h ${DP_DB_HOST} -u ${MYSQL_ADMIN_USER} -p ${MYSQL_ADMIN_PASSWORD} -P ${DP_DB_PORT} --regex '^(?!(kubeblocks\.kb_health_check$))' \
  ${params}
