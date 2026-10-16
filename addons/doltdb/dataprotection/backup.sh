#!/bin/bash
set -euo pipefail

: "${DP_BACKUP_NAME:?DP_BACKUP_NAME is required}"
: "${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required}"
: "${DP_BACKUP_INFO_FILE:?DP_BACKUP_INFO_FILE is required}"

export PATH="$PATH:${DP_DATASAFED_BIN_PATH:-}"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
STAGING_ROOT="${DOLT_BACKUP_STAGING_DIR:-${DATA_DIR}/.kb-doltdb-backup}"
WORK_DIR="${STAGING_ROOT}/work"
ARCHIVE="${DP_BACKUP_NAME}.tar.zst"
MANIFEST="${WORK_DIR}/manifest.tsv"

cleanup() {
  if [[ -n "${STAGING_ROOT:-}" && "$STAGING_ROOT" == "$DATA_DIR"/* ]]; then
    rm -rf "$STAGING_ROOT"
  fi
}
trap cleanup EXIT

if [[ "$DATA_DIR" != /* || "$DATA_DIR" == "/" ]]; then
  echo "invalid DATA_DIR: ${DATA_DIR}" >&2
  exit 1
fi

if [ ! -f "$MANIFEST" ]; then
  echo "backup staging manifest does not exist: ${MANIFEST}" >&2
  exit 1
fi

tar -C "$WORK_DIR" -cvf - manifest.tsv repos server-metadata database-metadata | datasafed push -z zstd-fastest - "$ARCHIVE"

TOTAL_SIZE="$(datasafed stat "$ARCHIVE" 2>/dev/null | awk '/TotalSize/ {print $2; exit}')"
echo "{\"totalSize\":\"${TOTAL_SIZE:-0}\"}" >"$DP_BACKUP_INFO_FILE" && sync
