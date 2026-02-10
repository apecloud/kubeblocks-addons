#!/usr/bin/env bash

# This script performs a full logical backup of Elasticsearch using elasticsearch-dump (multielasticdump).
# It dumps all indices' data, mappings, analyzers, aliases, settings, and templates,
# packages them into a tar archive, and pushes to backup storage via datasafed.

set -e
set -o errexit
set -x

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

ES_ENDPOINT="http://${DP_DB_HOST}.${KB_NAMESPACE}.svc.cluster.local:9200"

# Exit handler: write backup info on success, or touch exit file on failure
handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  else
    echo "{}" >"${DP_BACKUP_INFO_FILE}"
    exit 0
  fi
}
trap handle_exit EXIT

# Build authenticated endpoint URL for elasticdump
if [ -n "${ELASTIC_USER_PASSWORD}" ]; then
    ES_AUTH_ENDPOINT="http://elastic:${ELASTIC_USER_PASSWORD}@${DP_DB_HOST}.${KB_NAMESPACE}.svc.cluster.local:9200"
else
    ES_AUTH_ENDPOINT="${ES_ENDPOINT}"
fi

# Create temporary backup directory
BACKUP_DIR=/tmp/es-dump-backup
rm -rf ${BACKUP_DIR}
mkdir -p ${BACKUP_DIR}

echo "INFO: Starting elasticsearch-dump full backup"
echo "INFO: Elasticsearch endpoint: ${ES_ENDPOINT}"

# Default match pattern: only backup user indices (exclude system indices starting with ".")
# System indices (.kibana, .kibana_task_manager, .security, .tasks, .apm, etc.)
# are managed internally by Elasticsearch and Kibana. Restoring them from a backup
# will overwrite their internal migration/state tracking and cause errors (e.g. Kibana
# migration lock). Override with the MATCH env variable if needed.
MATCH_PATTERN="${MATCH:-^[^\.]}"
echo "INFO: Index match pattern: ${MATCH_PATTERN}"

# Set elasticdump options
DUMP_OPTS=""
if [ -n "${SCROLL_TIME}" ]; then
    DUMP_OPTS="${DUMP_OPTS} --scrollTime=${SCROLL_TIME}"
fi
if [ -n "${LIMIT}" ]; then
    DUMP_OPTS="${DUMP_OPTS} --limit=${LIMIT}"
fi

# Use multielasticdump to dump all matched indices
# Types: data (documents), mapping (index mappings), analyzer (custom analyzers),
#        alias (index aliases), settings (index settings), template (index templates)
multielasticdump \
  --direction=dump \
  --input="${ES_AUTH_ENDPOINT}" \
  --output="${BACKUP_DIR}" \
  --match="${MATCH_PATTERN}" \
  --includeType=data,mapping,analyzer,alias,settings,template \
  "${DUMP_OPTS}"

echo "INFO: elasticsearch-dump completed, packaging backup data"

# Tar and push to backup storage via datasafed
cd ${BACKUP_DIR}
tar -cf - . | datasafed push -z zstd-fastest - "/${DP_BACKUP_NAME}.tar.zst"

echo "INFO: Backup data pushed to storage successfully"

# Cleanup
rm -rf ${BACKUP_DIR}
