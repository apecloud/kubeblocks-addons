export PGPASSWORD=${DP_DB_PASSWORD}
# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export KB_BACKUP_WORKDIR=${VOLUME_DATA_DIR}/kb-backup

PSQL="psql -h ${DP_DB_HOST} -U ${DP_DB_USER} -d postgres"
global_last_switch_wal_time=$(date +%s)
global_last_purge_time=$(date +%s)
global_switch_wal_interval=300
global_stop_time=
global_old_size=0

if [[ ${SWITCH_WAL_INTERVAL_SECONDS} =~ ^[0-9]+$ ]];then
  global_switch_wal_interval=${SWITCH_WAL_INTERVAL_SECONDS}
fi

global_backup_in_secondary=
if [ "${TARGET_POD_ROLE}" == "primary" ]; then
   global_backup_in_secondary=f
elif [ "${TARGET_POD_ROLE}" == "secondary" ]; then
   global_backup_in_secondary=t
fi

# clean up expired logfiles, interval is 600s
function purge_expired_files() {
    local currentUnix=$(date +%s)
    info=$(DP_purge_expired_files ${currentUnix} ${global_last_purge_time} / 600)
    if [ ! -z "${info}" ]; then
       global_last_purge_time=${currentUnix}
       DP_log "cleanup expired wal-log files: ${info}"
       local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
       DP_save_backup_status_info "${TOTAL_SIZE}"
    fi
}

# switch wal log
function switch_wal_log() {
    local curr_time=$(date +%s)
    local diff_time=$((${curr_time}-${global_last_switch_wal_time}))
    if [[ ${diff_time} -lt ${global_switch_wal_interval} ]]; then
       return
    fi
    LAST_TRANS=$(pg_waldump $(${PSQL} -Atc "select pg_walfile_name(pg_current_wal_lsn())") --rmgr=Transaction 2>/dev/null |tail -n 1)
    if [ "${LAST_TRANS}" != "" ] && [ "$(find ${LOG_DIR}/archive_status/ -name '*.ready')" = "" ]; then
      DP_log "start to switch wal file"
      ${PSQL} -c "select pg_switch_wal()"
      for i in $(seq 1 60); do
        if [ "$(find ${LOG_DIR}/archive_status/ -name '*.ready')" != "" ]; then
          DP_log "switch wal file successfully"
          break;
        fi
        sleep 1
      done
    fi
    global_last_switch_wal_time=${curr_time}
}

# upload wal log
function upload_wal_log() {
    local TODAY_INCR_LOG=$(date +%Y%m%d);
    cd ${LOG_DIR}
    for i in $(ls -tr ./archive_status/ | grep .ready); do
      wal_name=${i%.*}
      LOG_STOP_TIME=$(pg_waldump ${wal_name} --rmgr=Transaction 2>/dev/null | grep 'desc: COMMIT' |tail -n 1|awk -F ' COMMIT ' '{print $2}'|awk -F ';' '{print $1}')
      if [[ ! -z $LOG_STOP_TIME ]];then
         global_stop_time=$(date -d "${LOG_STOP_TIME}" -u '+%Y-%m-%dT%H:%M:%SZ')
      fi
      if [ -f ${wal_name} ]; then
        DP_log "upload ${wal_name}"
        datasafed push -z zstd ${wal_name} "/${TODAY_INCR_LOG}/${wal_name}.zst"
        mv -f ./archive_status/${i} ./archive_status/${wal_name}.done;
      fi
    done
}

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

# get the start time for backup.status.timeRange
function get_start_time_for_range() {
   local OLDEST_FILE=$(datasafed list -f --recursive / -o json | jq -s -r '.[] | sort_by(.mtime) | .[] | .path' |head -n 1)
   if [ ! -z ${OLDEST_FILE} ]; then
     START_TIME=$(DP_analyze_start_time_from_datasafed ${OLDEST_FILE} get_wal_log_start_time pull_wal_log)
     echo ${START_TIME}
   fi
}

# save backup status info to sync file
function save_backup_status() {
    local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
    # if no size changes, return
    if [[ -z ${TOTAL_SIZE} || ${TOTAL_SIZE} -eq 0 || ${TOTAL_SIZE} == ${global_old_size} ]];then
       return
    fi
    global_old_size=${TOTAL_SIZE}
    local START_TIME=$(get_start_time_for_range)
    DP_save_backup_status_info "${TOTAL_SIZE}" "${START_TIME}" "${global_stop_time}"
}

function check_pg_process() {
    local is_ok=false
    for ((i=1;i<4;i++));do
      is_secondary=$(${PSQL} -Atc "select pg_is_in_recovery()")
      if [[ $? -eq 0  && (-z ${global_backup_in_secondary} || "${global_backup_in_secondary}" == "${is_secondary}") ]]; then
        is_ok=true
        break
      fi
      DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not OK, target role: ${TARGET_POD_ROLE}, pg_is_in_recovery: ${is_secondary}, retry detection!"
      sleep 1
    done
    if [[ ${is_ok} == "false" ]];then
      DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not OK, target role: ${TARGET_POD_ROLE}, pg_is_in_recovery: ${is_secondary}!"
      exit 1
    fi
}

# trap term signal
trap "echo 'Terminating...' && sync && exit 0" TERM
DP_log "start to archive wal logs"
while true; do

  # check if pg process is ok
  check_pg_process

  # switch wal log
  switch_wal_log

  # upload wal log
  upload_wal_log

  # save backup status which will be updated to `backup` CR by the sidecar
  save_backup_status

  # purge the expired wal logs
  purge_expired_files
  sleep ${LOG_ARCHIVE_SECONDS}
done