# shellcheck disable=SC2148

postgres_log_dir="${VOLUME_DATA_DIR}/logs"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
setup_logging WALG_BACKUP "${postgres_scripts_log_file}"

backup_base_path="$(dirname "$DP_BACKUP_BASE_PATH")/wal-g"
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export WALG_COMPRESSION_METHOD=zstd
export PGPASSWORD=${DP_DB_PASSWORD}
export DATASAFED_BACKEND_BASE_PATH=${backup_base_path}
# 20Gi for bundle file
export WALG_TAR_SIZE_THRESHOLD=21474836480

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

function get_backup_name() {
  line=$(tail -n 1 result.txt)
  if [[ $line == *"Wrote backup with name"* ]]; then
     echo "${line##* }"
  fi
}

function writeSentinelInBaseBackupPath() {
  content=${1}
  fileName=${2}
  export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
  echo "${content}" | datasafed push - "${fileName}"
  export DATASAFED_BACKEND_BASE_PATH=${backup_base_path}
}

trap handle_exit EXIT
set -e
# 1. do full backup
writeSentinelInBaseBackupPath "${backup_base_path}" "wal-g-backup-repo.path"
echo "Full backup using WAL-G: BEGIN"
PGHOST=${DP_DB_HOST} PGUSER=${DP_DB_USER} PGPORT=5432 wal-g backup-push "${DATA_DIR}" 2>&1 | tee result.txt
echo "Full backup using WAL-G: DONE"

set +e
echo "switch wal log"
PSQL="psql -h ${KB_CLUSTER_NAME}-${KB_COMP_NAME} -U ${DP_DB_USER} -d postgres"
${PSQL} -c "select pg_switch_wal();"

# 2. get backup name of the wal-g
backupName=$(get_backup_name)
if [[ -z ${backupName} ]] || [[ ${backupName} != "base_"* ]];then
   echo "ERROR: backup failed, can not get the backup name"
   exit 1
fi

# 3. add sentinel file for this backup CR
echo "add sentinel file for backup"
echo "" | datasafed push - "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"
writeSentinelInBaseBackupPath "${backupName}" "wal-g-backup-name"

# 4. stat startTime,stopTime,totalSize for this backup
sentinel_file="/basebackups_005/${backupName}_backup_stop_sentinel.json"
datasafed pull "${sentinel_file}" backup_stop_sentinel.json
result_json=$(cat backup_stop_sentinel.json)
STOP_TIME=$(echo "${result_json}" | jq -r ".FinishTime")
START_TIME=$(echo "${result_json}" | jq -r ".StartTime")
TOTAL_SIZE=$(echo "${result_json}" | jq -r ".CompressedSize")

# 5. update backup status
echo "write backup result"
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
echo "full backup DONE"
sync
