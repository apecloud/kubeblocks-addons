#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DATA_DIR=${DATA_DIR:-/bitnami/zookeeper/data}
BACKUP_DIR=/data/backup

echo "Restoring Zookeeper data directory..."

LATEST_BACKUP=$(ls -t "${BACKUP_DIR}" | head -1)
cp -r "${BACKUP_DIR}/${LATEST_BACKUP}" "${DATA_DIR}"

echo "Zookeeper data directory restored successfully."