#!/bin/bash
set -exo pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
mkdir -p "$RESTORE_DIR"

remote_backup_file="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list "$remote_backup_file")" = "$remote_backup_file" ]; then
  datasafed pull -d zstd-fastest "$remote_backup_file" - | tar -xvf - -C "$RESTORE_DIR"
fi

backup_file="$RESTORE_DIR/$DP_BACKUP_NAME"

if check_backup_file "$backup_file"; then
  echo "Backup file is valid."
else
  echo "Backup file is invalid." >&2
  exit 1
fi