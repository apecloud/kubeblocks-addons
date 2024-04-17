#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DATA_DIR=${DATA_DIR:-/bitnami/zookeeper/data}
BACKUP_NAME="zookeeper-data-$(date +%Y%m%d-%H%M%S).tar.zst"

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

echo "Backing up Zookeeper data directory..."

cd ${DATA_DIR}
tar -cvf - ./ | datasafed push -z zstd-fastest - "${BACKUP_NAME}"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}" && sync

echo "Zookeeper data directory backup completed successfully."