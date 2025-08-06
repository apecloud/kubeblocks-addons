# retention 8 days by default
retention_minute=""
if [ ! -z ${DP_TTL_SECONDS} ];then
  retention_minute=$((${DP_TTL_SECONDS}/60))
fi
export MONGODB_URI="mongodb://${DP_DB_USER}:${DP_DB_PASSWORD}@${DP_DB_HOST}:${DP_DB_PORT}/?authSource=admin"
export OPLOG_ARCHIVE_TIMEOUT_INTERVAL=${DP_ARCHIVE_INTERVAL}
export OPLOG_ARCHIVE_AFTER_SIZE=${ARCHIVE_AFTER_SIZE}
# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export WALG_COMPRESSION_METHOD=zstd
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
# retention time
export OPLOG_PITR_DISCOVERY_INTERVAL=168h
retryTimes=0
global_last_purge_time=$(date +%s)
wal_g_pid=0
old_size=0

do_oplog_push(){
  DP_log "start to archive oplog..."
  DP_log "wal-g oplog-push > /tmp/wal-g-oplog.log"
  wal-g oplog-push >/tmp/wal-g-oplog.log 2>&1 &
  wal_g_pid=$!
  sleep 1
  cat /tmp/wal-g-oplog.log
}

check_oplog_push_process(){
  # check wal-g oplog-push process
  ps -p $wal_g_pid >/dev/null
  if [ $? -ne 0 ]; then
    DP_error_log 'the process "wal-g oplog-push" does not exist!'
    errorLog=$(cat /tmp/wal-g-oplog.log)
    echo $errorLog && exit 1
  fi
  # check role of the connected mongodb
  export CLIENT=`which mongosh&&echo mongosh||echo mongo`
  isPrimary=$($CLIENT -u ${DP_DB_USER} -p ${DP_DB_PASSWORD} --port ${DP_DB_PORT} --host ${DP_DB_HOST} --authenticationDatabase admin  --eval 'rs.isMaster().ismaster' --quiet)
  if [ "${isPrimary}" != "true" ]; then
    DP_log "isPrimary: ${isPrimary}"
    retryTimes=$(($retryTimes+1))
  else
    retryTimes=0
  fi
  if [ $retryTimes -ge 3 ]; then
     DP_error_log "the current mongo instance is not a primary node, 3 attempts have been made!" && kill $wal_g_pid
  fi
}

# write the startTime and stopTime to backup.info file
dump_start_and_stop_time() {
   local TOTAL_SIZE=$(datasafed stat /oplog_005 | grep TotalSize | awk '{print $2}')
   # if no size changes, return
   if [[ -z ${TOTAL_SIZE} || ${TOTAL_SIZE} -eq 0 || ${TOTAL_SIZE} == ${old_size} ]];then
      return
   fi
   old_size=${TOTAL_SIZE}
   OLDEST_FILE=$(datasafed list -f -s mtime /oplog_005 | head -n 1)
   LATEST_FILE=$(datasafed list -f -s mtime /oplog_005 | tail -n 1)
   OLDEST_FILE=$(basename ${OLDEST_FILE}) && OLDEST_FILE=${OLDEST_FILE#*_} && LOG_START_TIME=${OLDEST_FILE%%.*}
   LATEST_FILE=$(basename ${LATEST_FILE}) && LATEST_FILE=${LATEST_FILE##*_} && LOG_STOP_TIME=${LATEST_FILE%%.*}
   if [ ! -z $LOG_START_TIME ]; then
       START_TIME=$(date -d "@${LOG_START_TIME}" -u '+%Y-%m-%dT%H:%M:%SZ')
       STOP_TIME=$(date -d "@${LOG_STOP_TIME}" -u '+%Y-%m-%dT%H:%M:%SZ')
       echo "{\"totalSize\":\"$TOTAL_SIZE\",\"timeRange\":{\"start\":\"${START_TIME}\",\"end\":\"${STOP_TIME}\"}}" > ${DP_BACKUP_INFO_FILE}
   fi
}
# purge the expired files, default interval is 60s
purge_expired_files() {
  local currentUnix=$(date +%s)
  info=$(DP_purge_expired_files ${currentUnix} ${global_last_purge_time} /oplog_005)
  if [ ! -z "${info}" ]; then
    global_last_purge_time=${currentUnix}
    DP_log "cleanup expired oplog files: ${info}"
    local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
    DP_save_backup_status_info "${TOTAL_SIZE}"
  fi
}

# create oplog push process
do_oplog_push
# trap term signal
trap "echo 'Terminating...' && kill $wal_g_pid" TERM
while true; do
  check_oplog_push_process
  sleep 1
  dump_start_and_stop_time
  # purge the expired oplog
  purge_expired_files
done