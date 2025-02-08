backup_base_path="$(dirname $DP_BACKUP_BASE_PATH)/wal-g/wal_005"
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export WALG_COMPRESSION_METHOD=zstd
export PGPASSWORD=${DP_DB_PASSWORD}
export DATASAFED_BACKEND_BASE_PATH=${backup_base_path}
export KB_BACKUP_WORKDIR=${VOLUME_DATA_DIR}/kb-backup
GLOBAL_OLD_SIZE=0

# get start time of the wal log
function get_wal_log_start_time() {
    local file="${1:?missing wal log name to analyze}"
    local START_TIME=$(pg_waldump $file --rmgr=Transaction 2>/dev/null | grep 'desc: COMMIT' |head -n 1|awk -F ' COMMIT ' '{print $2}'|awk -F ';' '{print $1}')
    if [[ ! -z ${START_TIME} ]];then
       START_TIME=$(date -d "${START_TIME}" -u '+%Y-%m-%dT%H:%M:%SZ')
       echo $START_TIME
   fi
}

# pull wal log and decompress to KB_BACKUP_WORKDIR dir
function pull_wal_log() {
   file="${1:?missing file name to pull}"
   # pull and decompress
   fileName=$(basename ${file})
   datasafed pull -d zstd ${file} "$(DP_get_file_name_without_ext ${fileName})"
}

function get_wal_log_end_time() {
    wal_file="${1:?missing file name to pull}"
    mkdir -p ${KB_BACKUP_WORKDIR} && cd ${KB_BACKUP_WORKDIR}
    pull_wal_log ${wal_file}
    wal_file_name=$(DP_get_file_name_without_ext `basename ${wal_file}`)
    local END_TIME=$(pg_waldump $wal_file_name --rmgr=Transaction 2>/dev/null | grep 'desc: COMMIT' |tail -n 1|awk -F ' COMMIT ' '{print $2}'|awk -F ';' '{print $1}')
    if [[ ! -z ${END_TIME} ]];then
       END_TIME=$(date -d "${END_TIME}" -u '+%Y-%m-%dT%H:%M:%SZ')
       echo $END_TIME
    fi
    rm -rf $wal_file_name
}


# save backup status info to sync file
function save_backup_status() {
    local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
    # if no size changes, return
    if [[ -z ${TOTAL_SIZE} || ${TOTAL_SIZE} -eq 0 || ${TOTAL_SIZE} == ${GLOBAL_OLD_SIZE} ]];then
       return
    fi
    GLOBAL_OLD_SIZE=${TOTAL_SIZE}
    local wal_files=$(datasafed list -f --recursive / -o json | jq -s -r '.[] | sort_by(.mtime) |.[] |.path')
    local OLDEST_FILE=$(echo $wal_files | tr ' ' '\n' |head -n 1)
    local LATEST_FILE=$(echo $wal_files | tr ' ' '\n' |tail -n 1)
    local START_TIME=
    local END_TIME=
    if [ ! -z ${OLDEST_FILE} ]; then
       START_TIME=$(DP_analyze_start_time_from_datasafed ${OLDEST_FILE} get_wal_log_start_time pull_wal_log)
    fi
    if [ ! -z ${LATEST_FILE} ]; then
       END_TIME=$(get_wal_log_end_time ${LATEST_FILE})
    fi
    DP_log "start time of the oldest wal: ${START_TIME}, end time of the latest wal: ${END_TIME}, total size: ${TOTAL_SIZE}"
    DP_save_backup_status_info "${TOTAL_SIZE}" "${START_TIME}" "${END_TIME}"
}

# trap term signal
trap "echo 'Terminating...' && exit 0" TERM
DP_log "start to collect wal infos"
while true; do
  save_backup_status
  sleep ${LOG_ARCHIVE_SECONDS}
done
