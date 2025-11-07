#!/usr/bin/env bash

set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

SNAPSHOT_DIR="${DATA_DIR}/_dp_snapshots"
mkdir -p "${SNAPSHOT_DIR}"
for snapshot in $(datasafed list /) ; do
  collection_name=${snapshot%.*}
  # skip file kubeblocks-backup.json which is not a snapshot
  if [ "${collection_name}" == "kubeblocks-backup" ]; then
    continue
  fi
  echo "INFO: start to restore collection ${collection_name}..."
  # download snapshot file
  datasafed pull "${snapshot}" "${SNAPSHOT_DIR}/${snapshot}"

  while true; do
    curl -X POST "http://${DP_DB_HOST}:6333/collections/${collection_name}/snapshots/upload?priority=snapshot" \
      -H 'Content-Type:multipart/form-data' \
      -F "snapshot=@${SNAPSHOT_DIR}/${snapshot}" > /tmp/qdrant-restore.log 2>&1
    if grep -q '"status":"ok"' /tmp/qdrant-restore.log; then
      echo "restore collection ${collection_name} successfully"
      break
    else
      echo "INFO: failed to restore collection ${collection_name}, retry..."
      sleep 5
    fi
  done
done