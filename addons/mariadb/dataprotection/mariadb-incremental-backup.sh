#!/bin/bash
set -euo pipefail

trap 'rc=$?; if [ "$rc" -ne 0 ]; then touch "${DP_BACKUP_INFO_FILE}.exit"; fi; exit "$rc"' EXIT

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
PARENT_DIR="${BACKUP_WORK_DIR}/parent"

if [ -z "${DP_PARENT_BACKUP_NAME:-}" ]; then
  echo "DP_PARENT_BACKUP_NAME is empty" >&2
  exit 1
fi

select_backup_account() {
  BACKUP_DB_USER="${DP_DB_USER}"
  BACKUP_DB_PASSWORD="${DP_DB_PASSWORD}"
  if [ -n "${MARIADB_INTERNAL_ROOT_USER:-}" ] && [ -n "${MARIADB_ROOT_PASSWORD:-}" ]; then
    BACKUP_DB_USER="${MARIADB_INTERNAL_ROOT_USER}"
    BACKUP_DB_PASSWORD="${MARIADB_ROOT_PASSWORD}"
  elif [ -n "${MYSQL_ADMIN_USER:-}" ] && [ -n "${MYSQL_ADMIN_PASSWORD:-}" ]; then
    BACKUP_DB_USER="${MYSQL_ADMIN_USER}"
    BACKUP_DB_PASSWORD="${MYSQL_ADMIN_PASSWORD}"
  fi
}

pull_backup() {
  local backup_name="$1"
  local destination="$2"
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${backup_name}/${DP_TARGET_RELATIVE_PATH}"
  rm -rf "$destination"
  mkdir -p "$destination"
  datasafed pull "${backup_name}.mbstream" - | mbstream -x -C "$destination"
}

select_backup_account
pull_backup "$DP_PARENT_BACKUP_NAME" "$PARENT_DIR"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

mariadb-backup --backup --slave-info --stream=mbstream \
  --incremental-basedir="$PARENT_DIR" \
  --host="$DP_DB_HOST" --port="${DP_DB_PORT:-3306}" \
  --user="$BACKUP_DB_USER" --password="$BACKUP_DB_PASSWORD" \
  --datadir="$DATA_DIR" --skip-ssl \
  | datasafed push - "/${DP_BACKUP_NAME}.mbstream"

TOTAL_SIZE=$(datasafed stat / | awk '/TotalSize/{print $2}')
echo "{\"totalSize\":\"${TOTAL_SIZE}\"}" > "$DP_BACKUP_INFO_FILE"
rm -rf "$PARENT_DIR"
