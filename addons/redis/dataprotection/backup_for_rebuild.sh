#!/bin/bash
set -e
set -o pipefail

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

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
cd ${DATA_DIR}
if [ -f ./nodes.conf ]; then
  datasafed push ./nodes.conf "nodes.conf"
fi
datasafed push ./users.acl "users.acl"
echo "INFO: save data file successfully"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}" && sync
