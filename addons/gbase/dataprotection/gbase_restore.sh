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

if [ $(remote_file_exists "${DP_BACKUP_NAME}.tar.gz") == "true" ]; then
   datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.tar.gz" - | tar -xzvf - -C  /
   echo "done!";
   exit 0
fi