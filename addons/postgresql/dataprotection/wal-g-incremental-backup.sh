#!/bin/bash
set -e
set -o pipefail

backup_base_path="$(dirname $DP_BACKUP_BASE_PATH)/wal-g"
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export WALG_COMPRESSION_METHOD=zstd
export PGPASSWORD=${DP_DB_PASSWORD}
export DATASAFED_BACKEND_BASE_PATH=${backup_base_path}
# incremental backup count limits
export WALG_DELTA_MAX_STEPS=100

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

function config_wal_g() {
    walg_dir=${VOLUME_DATA_DIR}/wal-g
    walg_env=${walg_dir}/env
    mkdir -p ${walg_dir}/env
    cp /etc/datasafed/datasafed.conf ${walg_dir}/datasafed.conf
    cp /usr/bin/wal-g ${walg_dir}/wal-g
    datasafed_base_path=${1:?missing datasafed_base_path}
    # config wal-g env
    # config WALG_PG_WAL_SIZE with wal_segment_size which fetched by psql
    # echo "" > ${walg_env}/WALG_PG_WAL_SIZE
    echo "${walg_dir}/datasafed.conf" > ${walg_env}/WALG_DATASAFED_CONFIG
    echo "${datasafed_base_path}" > ${walg_env}/DATASAFED_BACKEND_BASE_PATH
    echo "true" > ${walg_env}/PG_READY_RENAME
    echo "zstd" > ${walg_env}/WALG_COMPRESSION_METHOD
    if [ -n "${DATASAFED_ENCRYPTION_ALGORITHM}" ]; then
      echo "${DATASAFED_ENCRYPTION_ALGORITHM}" > ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM
    elif [ -f ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM ]; then
       rm ${walg_env}/DATASAFED_ENCRYPTION_ALGORITHM
    fi
    if [ -n "${DATASAFED_ENCRYPTION_PASS_PHRASE}" ]; then
       echo "${DATASAFED_ENCRYPTION_PASS_PHRASE}" > ${walg_env}/DATASAFED_ENCRYPTION_PASS_PHRASE
    elif [ -f ${walg_env}/DATASAFED_ENCRYPTION_PASS_PHRASE ]; then
       rm ${walg_env}/DATASAFED_ENCRYPTION_PASS_PHRASE
    fi
}

function getWalGSentinelInfo() {
  local sentinelFile=${1}
  local out=$(datasafed list ${sentinelFile})
  if [ "${out}" == "${sentinelFile}" ]; then
     datasafed pull "${sentinelFile}" ${sentinelFile}
     echo "$(cat ${sentinelFile})"
     return
  fi
}

function writeSentinelInBaseBackupPath() {
  content=${1}
  fileName=${2}
  export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
  echo "${content}" | datasafed push - "${fileName}"
  export DATASAFED_BACKEND_BASE_PATH=${backup_base_path}
}

function get_backup_name() {
  local parent_wal_g_backup_name=${1}
  line=$(cat result.txt | tail -n 1)
  if [[ $line == *"Wrote backup with name"* ]]; then
     cat result.txt | tail -n 1 | grep -o 'base_[0-9A-Za-z_]*'
     return
  fi
  if [[ $line == *"Finish LSN of backup ${parent_wal_g_backup_name} greater than current LSN"* ]]; then
     echo ${parent_wal_g_backup_name}
     return
  fi
}


trap handle_exit EXIT

# 1. check parent backup name
if [[ -z ${DP_PARENT_BACKUP_NAME} ]]; then
  echo "DP_PARENT_BACKUP_NAME is empty"
  exit 1
fi

# config wal-g
config_wal_g "$(dirname $DP_BACKUP_BASE_PATH)/wal-g"

# 2. parent backup name of the wal-g
export DATASAFED_BACKEND_BASE_PATH=$(dirname ${DP_BACKUP_BASE_PATH})/${DP_PARENT_BACKUP_NAME}
parentWalGBackupName=$(getWalGSentinelInfo "wal-g-backup-name")

# 1. incremental backup
set +e
writeSentinelInBaseBackupPath "${backup_base_path}" "wal-g-backup-repo.path"
PGHOST=${DP_DB_HOST} PGUSER=${DP_DB_USER} PGPORT=5432 wal-g backup-push ${DATA_DIR} --delta-from-name ${parentWalGBackupName} 2>&1 | tee result.txt

# 2. get backup name of the wal-g
backupName=$(get_backup_name "${parentWalGBackupName}")
if [[ -z ${backupName} ]] || [[ ${backupName} != "base_"* ]];then
   echo "ERROR: backup failed, can not get the backup name"
   exit 1
fi

set +e
echo "switch wal log"
PSQL="psql -h ${CLUSTER_COMPONENT_NAME}-${COMPONENT_NAME} -U ${DP_DB_USER} -d postgres"
${PSQL} -c "select pg_switch_wal();"

# 3. add sentinel file for this backup CR
echo "" | datasafed push - "/basebackups_005/${backupName}_dp_${DP_BACKUP_NAME}"
writeSentinelInBaseBackupPath "${backupName}" "wal-g-backup-name"


# 4. stat startTime,stopTime,totalSize for this backup
sentinel_file="/basebackups_005/${backupName}_backup_stop_sentinel.json"
datasafed pull ${sentinel_file} backup_stop_sentinel.json
result_json=$(cat backup_stop_sentinel.json)
STOP_TIME=$(echo $result_json | jq -r ".FinishTime")
START_TIME=$(echo $result_json | jq -r ".StartTime")
TOTAL_SIZE=$(echo $result_json | jq -r ".CompressedSize")
if [[ "${backupName}" == "${parentWalGBackupName}" ]]; then
   TOTAL_SIZE=0
   START_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
   STOP_TIME=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
fi

# 5. update backup status
echo "{\"totalSize\":\"$TOTAL_SIZE\",\"extras\":[{\"wal-g-backup-name\":\"${backupName}\"}],\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" >"${DP_BACKUP_INFO_FILE}"
