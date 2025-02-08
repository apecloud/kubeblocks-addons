#!/bin/bash
backup_base_path="$(dirname $DP_BACKUP_BASE_PATH)/wal-g"
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$backup_base_path"

base_backup_list=$(datasafed list /basebackups_005 -d)
if [[ -z ${base_backup_list} ]]; then
  datasafed rm -r /wal_005
fi