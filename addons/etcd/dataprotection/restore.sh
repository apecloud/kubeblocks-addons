#!/bin/bash
set -exo pipefail

CUR_PATH="$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=./common.sh
source "${CUR_PATH}/common.sh"

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

DATA_DIR=/data
mkdir -p ${DATA_DIR}
res=$(find ${DATA_DIR} -type f)
data_protection_file=${DATA_DIR}/.kb-data-protection
if [ ! -z "${res}" ] && [ ! -f ${data_protection_file} ]; then
	echo "${DATA_DIR} is not empty! Please make sure that the directory is empty before restoring the backup."
	exit 1
fi

touch ${data_protection_file}

remoteBackupFile="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list ${remoteBackupFile})" == "${remoteBackupFile}" ]; then
  datasafed pull -d zstd-fastest "${remoteBackupFile}" - | tar -xvf - -C ${DATA_DIR}
else
  datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | tar -xzvf - -C ${DATA_DIR}
fi

backupFile=${DATA_DIR}/${DP_BACKUP_NAME}
ENDPOINTS=${DP_DB_HOST}.${KB_NAMESPACE}.svc${CLUSTER_DOMAIN}:2379

check_backup_file ${backupFile}

# https://etcd.io/docs/v3.5/op-guide/recovery/ restoring with revision bump if needed
execEtcdctl $ENDPOINTS snapshot restore ${backupFile}

rm -rf ${data_protection_file} && sync