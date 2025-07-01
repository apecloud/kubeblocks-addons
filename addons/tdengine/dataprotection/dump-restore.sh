set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

mkdir -p ${BACKUP_DIR}/${DP_BACKUP_NAME}
datasafed pull -d zstd-fastest "${DP_BACKUP_NAME}.tar.zst" - | tar -xvf - -C "${BACKUP_DIR}"
taosdump -h ${DP_DB_HOST} -P ${DP_DB_PORT} -p${TAOS_ROOT_PASSWORD} -i ${BACKUP_DIR}/${DP_BACKUP_NAME}