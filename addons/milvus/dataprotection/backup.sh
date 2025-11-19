#!/bin/bash

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit $exit_code
  fi
}

trap handle_exit EXIT
setStorageConfig

./milvus-backup create -n "$BACKUP_NAME"

# use datasafed to get backup size
# if we do not write into $DP_BACKUP_INFO_FILE, the backup job will stuck
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
DP_save_backup_status_info "$TOTAL_SIZE"
