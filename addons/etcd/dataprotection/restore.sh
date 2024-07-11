set -exo pipefail
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
# touch placeholder file
touch ${data_protection_file}

backupFile="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list ${backupFile})" == "${backupFile}" ]; then
    datasafed pull -d zstd-fastest "${backupFile}" - | tar -xvf - -C ${DATA_DIR}
else
    datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | tar -xzvf - -C ${DATA_DIR}
fi
ENDPOINTS=$DP_DB_HOST:

# https://etcd.io/docs/v3.5/op-guide/recovery/ restoring with revision bump
etcdctl --endpoints=$ENDPOINTS snapshot restore ${DATA_DIR}/${DP_BACKUP_NAME} --bump-revision 1000000000 --mark-compacted
rm -rf ${data_protection_file} && sync
