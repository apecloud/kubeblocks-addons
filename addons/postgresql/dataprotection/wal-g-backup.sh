backup_base_path="/${KB_NAMESPACE}/${KB_CLUSTER_NAME}-${KB_CLUSTER_UID}/${KB_COMP_NAME}/wal-g"
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
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
  line=$(cat result.txt | tail -n 1)
  if [[ $line == *"Wrote backup with name"* ]]; then
     echo ${line##* }
  fi
}

trap handle_exit EXIT
set -e
# 1. do full backup
PGHOST=${DP_DB_HOST} PGUSER=${DP_DB_USER} PGPORT=5432 wal-g backup-push ${DATA_DIR} 2>&1 | tee result.txt

# 2. get backup name of the wal-g
backupName=$(get_backup_name)
if [[ -z ${backupName} ]] || [[ ${backupName} != "base_"* ]];then
   echo "{\"path\":\"${backup_base_path}/basebackups_005\"}" >"${DP_BACKUP_INFO_FILE}"
   echo "ERROR: backup failed, can not get the backup name"
   exit 1
fi
# 3. add sentinel file for this backup CR
echo "" | datasafed push - "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"

# 4. stat startTime,stopTime,totalSize for this backup
sentinel_file="/basebackups_005/${backupName}_backup_stop_sentinel.json"
datasafed pull ${sentinel_file} backup_stop_sentinel.json
result_json=$(cat backup_stop_sentinel.json)
STOP_TIME=$(echo $result_json | jq -r ".FinishTime")
START_TIME=$(echo $result_json | jq -r ".StartTime")

# 5. update backup status
backupFilePath=/basebackups_005/${backupName}
TOTAL_SIZE=$(datasafed stat ${backupFilePath} | grep TotalSize | awk '{print $2}')
echo "{\"path\":\"${backup_base_path}${backupFilePath}\",\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"