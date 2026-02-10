#!/usr/bin/env bash

# This script performs a full logical restore of Elasticsearch using elasticsearch-dump (multielasticdump).
# It pulls the backup archive from storage, extracts it, and restores all indices'
# data, mappings, analyzers, aliases, settings, and templates.

set -e
set -o errexit
set -x

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

ES_ENDPOINT="http://${DP_DB_HOST}.${KB_NAMESPACE}.svc.cluster.local:9200"

# Exit handler
handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

# Build authenticated endpoint URL for elasticdump
if [ -n "${ELASTIC_USER_PASSWORD}" ]; then
    ES_AUTH_ENDPOINT="http://elastic:${ELASTIC_USER_PASSWORD}@${DP_DB_HOST}.${KB_NAMESPACE}.svc.cluster.local:9200"
else
    ES_AUTH_ENDPOINT="${ES_ENDPOINT}"
fi

# Create temporary restore directory
RESTORE_DIR=/tmp/es-dump-restore
rm -rf ${RESTORE_DIR}
mkdir -p ${RESTORE_DIR}

echo "INFO: Pulling backup data from storage"

# Pull and extract backup data
datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.tar.zst" - | tar -xf - -C ${RESTORE_DIR}

echo "INFO: Backup data extracted to ${RESTORE_DIR}"
ls -la ${RESTORE_DIR}

# Safety measure: remove any system index dump files (starting with ".") from restore directory.
# System indices (.kibana, .kibana_task_manager, .security, .tasks, etc.) are managed internally
# by Elasticsearch and Kibana. Restoring them overwrites their migration/state tracking and causes
# errors such as Kibana migration lock loops.
echo "INFO: Removing system index dump files (starting with '.') from restore directory"
for f in "${RESTORE_DIR}"/.*; do
    case "$(basename "$f")" in
        .|..) continue ;;
        *)
            echo "INFO: Removing system index dump file: $f"
            rm -f "$f"
            ;;
    esac
done

echo "INFO: Starting elasticsearch-dump restore"

# Set elasticdump options
DUMP_OPTS=""
if [ -n "${SCROLL_TIME}" ]; then
    DUMP_OPTS="${DUMP_OPTS} --scrollTime=${SCROLL_TIME}"
fi
if [ -n "${LIMIT}" ]; then
    DUMP_OPTS="${DUMP_OPTS} --limit=${LIMIT}"
fi

# Use multielasticdump to restore all indices
multielasticdump \
  --direction=load \
  --input="${RESTORE_DIR}" \
  --output="${ES_AUTH_ENDPOINT}" \
  "${DUMP_OPTS}"

echo "INFO: elasticsearch-dump restore completed"

# Cleanup
rm -rf ${RESTORE_DIR}

echo "INFO: Elasticsearch restore finished successfully"
