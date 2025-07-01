set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

mkdir -p ${BACKUP_DIR}/${DP_BACKUP_NAME}
taosdump -h ${DP_DB_HOST} -P ${DP_DB_PORT} -p${DP_DB_PASSWORD} --all-databases -o ${BACKUP_DIR}/${DP_BACKUP_NAME}

cd ${BACKUP_DIR}
tar -cvf - "${DP_BACKUP_NAME}" | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst"
rm -rf ${BACKUP_DIR}/${DP_BACKUP_NAME}

TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}"