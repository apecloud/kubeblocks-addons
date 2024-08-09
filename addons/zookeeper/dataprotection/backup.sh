#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
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

java -cp /zoocreeper.jar  com.boundary.zoocreeper.Backup \
-z ${DP_DB_HOST}:${MY_ZOOKEEPER_ZOOKEEPER_SERVICE_PORT_CLIENT} --compress | \
datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.backup.json"

TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}"