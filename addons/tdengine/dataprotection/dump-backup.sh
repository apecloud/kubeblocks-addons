set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

function handle_exit() {
  exit_code=$?
  if [ -d ${BACKUP_DIR}/${DP_BACKUP_NAME} ]; then
     rm -rf ${BACKUP_DIR}/${DP_BACKUP_NAME}
  fi
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"

    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
trap handle_exit EXIT

mkdir -p ${BACKUP_DIR}/${DP_BACKUP_NAME}
taosdump -h ${DP_DB_HOST} -P ${DP_DB_PORT} -p${DP_DB_PASSWORD} --all-databases -o ${BACKUP_DIR}/${DP_BACKUP_NAME}

# TODO: 先按数据库tar，后续测出来备份速度不满意就按直接遍历push。 如果还是不行，可能要用到nfs/pvc挂载模式了
function push_backups() {
  cd ${BACKUP_DIR}/${DP_BACKUP_NAME}
  for dir in $(find . -mindepth 1 -maxdepth 1 -type d); do
    dir_name=$(basename ${dir})
    echo "$(date) push backup file: ${dir_name}"
    tar -cvf - "${dir}" | datasafed push -z zstd-fastest - "/${DP_BACKUP_NAME}/${dir_name}.tar.zst"
  done
  for file in $(find . -maxdepth 1 -type f); do
    file_name=$(basename ${file})
    echo "$(date) push backup file: ${file_name}"
    datasafed push -z zstd-fastest ${file} "/${DP_BACKUP_NAME}/${file_name}.zst"
  done
}

push_backups

rm -rf ${BACKUP_DIR}/${DP_BACKUP_NAME}
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}"