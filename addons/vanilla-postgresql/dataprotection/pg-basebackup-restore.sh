#!/bin/bash

set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
function remote_file_exists() {
    out=$(datasafed list "$1")
    if [ "${out}" == "$1" ]; then
        echo "true"
        return
    fi
    echo "false"
}

mkdir -p "${DATA_DIR}";

if [ "$(remote_file_exists "${DP_BACKUP_NAME}.tar.zst")" == "true" ]; then
  datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.tar.zst" - | tar -xvf - -C "${DATA_DIR}/"
  touch "${DATA_DIR}/kb-restore.signal"
  echo "done!";
  exit 0
fi

echo "done!";