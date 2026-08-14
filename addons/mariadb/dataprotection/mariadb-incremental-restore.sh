#!/bin/bash
set -euo pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
BASE_DIR="${BACKUP_WORK_DIR}/base"
INCS_DIR="${BACKUP_WORK_DIR}/increments"

if [ -z "${DP_BASE_BACKUP_NAME:-}" ]; then
  echo "DP_BASE_BACKUP_NAME is empty" >&2
  exit 1
fi

pull_backup() {
  local backup_name="$1"
  local destination="$2"
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_ROOT_PATH}/${backup_name}/${DP_TARGET_RELATIVE_PATH}"
  rm -rf "$destination"
  mkdir -p "$destination"
  datasafed pull "${backup_name}.mbstream" - | mbstream -x -C "$destination"
}

rm -rf "$BASE_DIR" "$INCS_DIR"
pull_backup "$DP_BASE_BACKUP_NAME" "$BASE_DIR"
mariadb-backup --prepare --target-dir="$BASE_DIR"

ancestor_names="${DP_ANCESTOR_INCREMENTAL_BACKUP_NAMES:-}"
if [ -n "$ancestor_names" ]; then
  IFS=',' read -r -a ancestors <<< "$ancestor_names"
  for backup_name in "${ancestors[@]}"; do
    pull_backup "$backup_name" "$INCS_DIR/$backup_name"
    mariadb-backup --prepare --target-dir="$BASE_DIR" \
      --incremental-dir="$INCS_DIR/$backup_name"
    rm -rf "$INCS_DIR/$backup_name"
  done
fi

pull_backup "$DP_BACKUP_NAME" "$INCS_DIR/$DP_BACKUP_NAME"
mariadb-backup --prepare --target-dir="$BASE_DIR" \
  --incremental-dir="$INCS_DIR/$DP_BACKUP_NAME"

anchor_file=""
for info in mariadb_backup_binlog_info xtrabackup_binlog_info; do
  if [ -s "$INCS_DIR/$DP_BACKUP_NAME/$info" ]; then
    anchor_file="$INCS_DIR/$DP_BACKUP_NAME/$info"
    break
  fi
done
[ -n "$anchor_file" ] || {
  echo "final incremental backup has no binlog coordinates" >&2
  exit 1
}

find "$DATA_DIR" -mindepth 1 -maxdepth 1 -exec rm -rf -- {} +
mariadb-backup --copy-back --target-dir="$BASE_DIR" --datadir="$DATA_DIR"
cp "$anchor_file" "$DATA_DIR/.kb-pitr-binlog-info"
chown -R mysql:mysql "$DATA_DIR"
chmod -R 750 "$DATA_DIR"
rm -rf "$BASE_DIR" "$INCS_DIR"
