# Copyright ApeCloud Co., Ltd. All Rights Reserved.
# SPDX-License-Identifier: LicenseRef-KubeBlocks-Enterprise
# shellcheck shell=bash

set -e
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

# create backup directory
if [[ ! -d "${BACKUP_DIR}/${DP_BACKUP_NAME}" ]]; then
  mkdir -p "${BACKUP_DIR}/${DP_BACKUP_NAME}"
fi

# do backup sql
# with options:
# if specify MEDIANAME, the all backups must be COMPRESSED or UNCOMPRESSED.
# MEDIANAME: an id to manager the backups
# NAME: backup set name in the media
# METADATA_ONLY: equals to SNAPSHOT
# NOINIT/INIT: by default is MOINIT, append your backups. INIT: overwrite the backups with same meida, retain media header.
# FORMAT: init the medias and all backupsets will invalid in the medis, be carefully to use it. By default is NOFORMAT.
# Fail-fast: a backup that is missing any database must never be reported as
# successful, so any single database backup failure fails the whole action.
# (A "partial success" would be more dangerous than a hard failure -- unless the
# DataProtection controller and the restore path treat missing databases as a
# failure signal, a caller could later use an incomplete backup as if it were
# complete.)
if ! load_database_names include-master; then
  DP_error_log "failed to enumerate database names; failing the backup action"
  exit 1
fi
for database in "${DP_DATABASE_NAMES[@]}"; do
  DP_log "start to backup database ${database}"
  if ! backup_database_with_full "${database}"; then
     DP_error_log "backup database ${database} failed; failing the backup action"
     exit 1
  fi
done
# push backup
push_backups
save_backup_status
