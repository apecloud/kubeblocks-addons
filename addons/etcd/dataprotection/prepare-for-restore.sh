#!/bin/bash
set -exo pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

if [ "$H_SCALE" == "true" ]; then
  touch "/var/run/etcd/hscale-flag"
  exit 0
fi

mkdir -p "$BACKUP_DIR"

remote_backup_file="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list "$remote_backup_file")" = "$remote_backup_file" ]; then
  datasafed pull -d zstd-fastest "$remote_backup_file" - | tar -xvf - -C "$BACKUP_DIR"
fi
