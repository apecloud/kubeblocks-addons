#!/bin/bash
set -exo pipefail

# shellcheck disable=SC1091
. "/scripts/common.sh"

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
mkdir -p "$RESTORE_DIR"

remote_backup_file="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list "$remote_backup_file")" = "$remote_backup_file" ]; then
  datasafed pull -d zstd-fastest "$remote_backup_file" - | tar -xvf - -C "$RESTORE_DIR"
fi

backup_file="$RESTORE_DIR/$DP_BACKUP_NAME"
check_backup_file "$backup_file" || error_exit "Backup file is invalid"