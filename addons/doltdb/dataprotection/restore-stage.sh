#!/bin/bash
set -euo pipefail

: "${DP_BACKUP_NAME:?DP_BACKUP_NAME is required}"
: "${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required}"

export PATH="$PATH:${DP_DATASAFED_BIN_PATH:-}"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
STAGING_ROOT="${DOLT_RESTORE_STAGING_DIR:-${DATA_DIR}/.kb-doltdb-restore}"
WORK_DIR="${STAGING_ROOT}/current"
ARCHIVE="${DP_BACKUP_NAME}.tar.zst"
MANIFEST="${WORK_DIR}/manifest.tsv"

if [[ "$DATA_DIR" != /* || "$DATA_DIR" == "/" ]]; then
  echo "invalid DATA_DIR: ${DATA_DIR}" >&2
  exit 1
fi
if [[ "$STAGING_ROOT" != "$DATA_DIR"/* ]]; then
  echo "invalid DOLT_RESTORE_STAGING_DIR: ${STAGING_ROOT}" >&2
  exit 1
fi

rm -rf "$STAGING_ROOT"
mkdir -p "$WORK_DIR"

if ! datasafed list "$ARCHIVE" 2>/dev/null | grep -Fxq "$ARCHIVE"; then
  echo "backup archive ${ARCHIVE} not found" >&2
  exit 1
fi

datasafed pull -d zstd-fastest "$ARCHIVE" - | tar -xf - -C "$WORK_DIR"

if [ ! -f "$MANIFEST" ]; then
  echo "backup archive ${ARCHIVE} does not contain manifest.tsv" >&2
  exit 1
fi

found=0
while IFS=$'\t' read -r db_name repo_rel; do
  [ -n "$db_name" ] || continue
  case "$db_name" in
    */*|.*|*..*)
      echo "invalid database name in backup manifest: ${db_name}" >&2
      exit 1
      ;;
  esac
  case "$repo_rel" in
    repos/*) ;;
    *)
      echo "invalid repository path in backup manifest: ${repo_rel}" >&2
      exit 1
      ;;
  esac
  if [ ! -d "${WORK_DIR}/${repo_rel}" ]; then
    echo "repository path from backup manifest does not exist: ${repo_rel}" >&2
    exit 1
  fi
  found=1
done <"$MANIFEST"

if [ "$found" -eq 0 ]; then
  echo "backup archive did not contain Dolt databases"
fi

if [ -d "${WORK_DIR}/server-metadata" ]; then
  echo "server metadata is present in the backup archive; leaving it staged for review"
fi

printf '%s\n' "$DP_BACKUP_NAME" >"${STAGING_ROOT}/backup-name"
chmod -R a+rX "$STAGING_ROOT"
sync
