#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
function remote_file_exists() {
    local out=$(datasafed list $1)
    if [ "${out}" == "$1" ]; then
        echo "true"
        return
    fi
    echo "false"
}

if [[ $(remote_file_exists "${DP_BACKUP_NAME}.tar.gz") == "true" ]]; then
  echo "Backup file ${DP_BACKUP_NAME}.tar.gz exists. Proceeding with download and extraction..."

  datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | tar -xzvf - -C "/"
  echo "DP_BACKUP_NAME=${DP_BACKUP_NAME}" > /data/backup/envfile
  echo "Done!"
  exit 0
else
  echo "Backup ${DP_BACKUP_NAME}.tar.gz does not exist."
  exit 1
fi