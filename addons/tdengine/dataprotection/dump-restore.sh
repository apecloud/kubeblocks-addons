set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

mkdir -p ${BACKUP_DIR}/${DP_BACKUP_NAME}
# download the backup files
for file in $(datasafed list ${DP_BACKUP_NAME} -r -f); do
 file_name=${file#${DP_BACKUP_NAME}/}
 echo "download ${file_name} to ${BACKUP_DIR}/${DP_BACKUP_NAME}/${file_name}"
 if [[ "${file_name}" == *".tar.zst" ]]; then
   datasafed pull -d zstd-fastest "${file}" - | tar -xvf - -C ${BACKUP_DIR}/${DP_BACKUP_NAME}
 else
   file_name=${file_name%.zst}
   datasafed pull -d zstd-fastest "${file}" "${BACKUP_DIR}/${DP_BACKUP_NAME}/${file_name}"
 fi
done

taosdump -h ${DP_DB_HOST} -P ${DP_DB_PORT} -p${TAOS_ROOT_PASSWORD} -i ${BACKUP_DIR}/${DP_BACKUP_NAME} > ${BACKUP_DIR}/restore.log 2>&1
rm -rf ${BACKUP_DIR}/${DP_BACKUP_NAME}