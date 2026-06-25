#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CASE_SCRIPT="${SCRIPT_DIR}/qdrant_api_key_backup_restore_e2e.sh"
RUN_LIFECYCLE_CHECK="${RUN_LIFECYCLE_CHECK:-true}"

run_case() {
  local case_name="$1"
  local tls_enabled="$2"
  local api_key_enabled="$3"
  local cluster_name="qdrant-${case_name}"

  echo "INFO: running qdrant e2e case ${case_name} TLS=${tls_enabled} API key=${api_key_enabled}"
  CLUSTER_NAME="$cluster_name" \
    RESTORE_CLUSTER_NAME="${cluster_name}-restore" \
    BACKUP_NAME="${cluster_name}-backup" \
    QDRANT_COLLECTION="${case_name}-collection" \
    QDRANT_POINT_SOURCE="${case_name}" \
    QDRANT_API_KEY="${case_name}-key" \
    QDRANT_TLS_ENABLED="$tls_enabled" \
    API_KEY_ENABLED="$api_key_enabled" \
    RUN_LIFECYCLE_CHECK="$RUN_LIFECYCLE_CHECK" \
    "$CASE_SCRIPT"
}

run_case "tls-off-api-key-off" "false" "false"
run_case "tls-off-api-key-on" "false" "true"
run_case "tls-on-api-key-off" "true" "false"
run_case "tls-on-api-key-on" "true" "true"

echo "INFO: qdrant TLS/API-key lifecycle backup/restore e2e matrix passed"
