#!/usr/bin/env bash

set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
DATASAFED_BACKEND_BASE_PATH="$(dirname $DP_BACKUP_BASE_PATH)"
export DATASAFED_BACKEND_BASE_PATH

QDRANT_COMMON_FILE="${QDRANT_COMMON_FILE:-/qdrant/scripts/common.sh}"
if [ -r "$QDRANT_COMMON_FILE" ]; then
  # shellcheck disable=SC1090
  . "$QDRANT_COMMON_FILE"
fi

qdrant_set_tls_variables

for pod in $(datasafed list /); do
  for file in $(datasafed list "/$pod/") ; do
    snapshot=$(basename "$file")
    collection_name=${snapshot%.*}
    # skip file kubeblocks-backup.json which is not a snapshot
    if [ "${collection_name}" == "kubeblocks-backup" ]; then
      continue
    fi
    echo "INFO: start to restore collection ${collection_name} in ${pod}..."

    while true; do
      datasafed pull "${file}" - | qdrant_curl --retry 3 -sS -f -X POST "${SCHEME}://${DP_DB_HOST}:6333/collections/${collection_name}/snapshots/upload?priority=snapshot" \
        -H 'Content-Type:multipart/form-data' \
        -F "snapshot=@-;filename=${snapshot}" > /tmp/qdrant-restore.log 2>&1
      cat /tmp/qdrant-restore.log
      echo ""
      if grep -q '"status":"ok"' /tmp/qdrant-restore.log; then
        echo "restore collection ${collection_name} in ${pod} successfully"
        break
      else
        echo "INFO: failed to restore collection ${collection_name} in ${pod}, retry..."
        sleep 5
      fi
    done
  done
done
