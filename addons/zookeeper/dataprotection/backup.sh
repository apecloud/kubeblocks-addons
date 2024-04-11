#!/bin/bash

set -o errexit
set -o pipefail
set -o nounset

DATA_DIR=${DATA_DIR:-/bitnami/zookeeper/data}
BACKUP_DIR=/data/backup

mkdir -p "${BACKUP_DIR}"

echo "Backing up Zookeeper data directory..."
cp -r "${DATA_DIR}" "${BACKUP_DIR}/zookeeper-data-$(date +%Y%m%d-%H%M%S)"

echo "Zookeeper data directory backup completed successfully."