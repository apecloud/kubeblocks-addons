#!/bin/bash
set -ex

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

RESTORE_DIR=/restore
mkdir -p ${RESTORE_DIR}

remoteBackupFile="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list "${remoteBackupFile}")" = "${remoteBackupFile}" ]; then
  datasafed pull -d zstd-fastest "${remoteBackupFile}" - | tar -xvf - -C ${RESTORE_DIR}
fi

backupFile=${RESTORE_DIR}/${DP_BACKUP_NAME}
ENDPOINTS=${DP_DB_HOST}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379

if check_backup_file "${backupFile}"; then
  echo "Backup file is valid"
else
  echo "Backup file is invalid"
  exit 1
fi

# https://etcd.io/docs/v3.5/op-guide/recovery/ restoring with revision bump if needed
exec_etcdctl "$ENDPOINTS" snapshot restore "${backupFile}"