#!/bin/bash
set -exo pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

restore_dir=/restore
mkdir -p ${restore_dir}
remote_backup_file="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list "${remote_backup_file}")" = "${remote_backup_file}" ]; then
  datasafed pull -d zstd-fastest "${remote_backup_file}" - | tar -xvf - -C ${restore_dir}
fi

backup_file=${restore_dir}/${DP_BACKUP_NAME}
endpoint=${DP_DB_HOST}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379

if check_backup_file "${backup_file}"; then
  echo "Backup file is valid"
else
  echo "Backup file is invalid"
  exit 1
fi

# https://etcd.io/docs/v3.5/op-guide/recovery/ restoring with revision bump if needed
exec_etcdctl "$endpoint" snapshot restore "${backup_file}"