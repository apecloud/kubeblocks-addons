#!/bin/bash

set -exo pipefail

cat /etc/datasafed/datasafed.conf
toolConfig=/etc/datasafed/datasafed.conf

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists

function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

# use etcdctl create snapshot
tlsDir=$TLS_DIR
ENDPOINTS=${DP_DB_HOST}.default.svc.cluster.local:2379

if [ -d $tlsDir ]; then
  etcdctl --endpoints=$ENDPOINTS --cacert=${tlsDir}/ca.crt --cert=${tlsDir}/tls.crt --key=${tlsDir}/tls.key snapshot save ${DP_BACKUP_NAME}
  etcdctl --endpoints=$ENDPOINTS --cacert=${tlsDir}/ca.crt --cert=${tlsDir}/tls.crt --key=${tlsDir}/tls.key --write-out=table snapshot status ${DP_BACKUP_NAME}
else
  etcdctl --endpoints=$ENDPOINTS snapshot save ${DP_BACKUP_NAME}
  etcdctl --endpoints=$ENDPOINTS --write-out=table snapshot status ${DP_BACKUP_NAME}
fi

# use datasafed to get backup size
# if we do not write into $DP_BACKUP_INFO_FILE, the backup job will stuck
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

tar -cvf - ${DP_BACKUP_NAME} | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst"

TOTAL_SIZE=$(datasafed stat ${DP_BACKUP_NAME} | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}" && sync
