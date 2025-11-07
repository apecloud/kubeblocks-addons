#!/bin/bash
# export wal-g environments
export WALG_MYSQL_DATASOURCE_NAME="${DP_DB_USER}:${DP_DB_PASSWORD}@tcp(${DP_DB_HOST}:${DP_DB_PORT})/mysql"
export WALG_COMPRESSION_METHOD=zstd
# use datasafed and default config
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export WALG_MYSQL_CHECK_GTIDS=true
export MYSQL_PWD=${DP_DB_PASSWORD}
# work directory to save necessary file for backup
export KB_BACKUP_WORKDIR=${VOLUME_DATA_DIR}/kb-backup

# get binlog basename
MYSQL_CMD="mysql -u ${DP_DB_USER} -h ${DP_DB_HOST} -N"
log_bin_basename=$(${MYSQL_CMD} -e "SHOW VARIABLES LIKE 'log_bin_basename';" | awk -F'\t' '{print $2}')
if [ -z ${log_bin_basename} ]; then
   echo "ERROR: pod/${DP_TARGET_POD_NAME} connect failed."
   exit 1
fi
LOG_DIR=$(dirname $log_bin_basename)
LOG_PREFIX=$(basename $log_bin_basename)

global_latest_bin_log=""
global_last_flush_logs_time=$(date +%s)
global_last_purge_time=$(date +%s)
global_old_size=0
global_flush_bin_logs_interval=600

if [[ ${DP_ARCHIVE_INTERVAL} =~ ^[0-9]+s$ ]];then
  global_flush_bin_logs_interval=${DP_ARCHIVE_INTERVAL%s}
fi

# checks if the mysql process is ok
function check_mysql_process() {
    is_ok=false
    for ((i=1;i<4;i++));do
      role=$(${MYSQL_CMD} -e "select role from information_schema.wesql_cluster_local;" | head -n 1)
      if [[ $? -eq 0  && (-z ${TARGET_POD_ROLE} || "${TARGET_POD_ROLE,,}" == "${role,,}") ]]; then
        is_ok=true
        break
      fi
      DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not OK, target role: ${TARGET_POD_ROLE}, current role: ${role}, retry detection!"
      sleep 1
    done
    if [[ ${is_ok} == "false" ]];then
      DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not OK, target role: ${TARGET_POD_ROLE}, current role: ${role}!"
      exit 1
    fi
}

# clean up expired logfiles, interval is 60s
function purge_expired_files() {
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
  local currentUnix=$(date +%s)
  info=$(DP_purge_expired_files ${currentUnix} ${global_last_purge_time})
  if [ ! -z "${info}" ]; then
    global_last_purge_time=${currentUnix}
    DP_log "cleanup expired binlog files: ${info}"
    local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
    DP_save_backup_status_info "${TOTAL_SIZE}"
  fi
}

# flush bin logs, interval is 600s by default
function flush_binlogs() {
  local binlog=$(ls -Ft ${LOG_DIR}/|grep -e "^${LOG_PREFIX}.*[[:digit:]]$" |head -n 1)
  if [ -z ${binlog} ]; then
     return
  fi
  local curr_time=$(date +%s)
  # if size greater than FLUSH_BINLOG_AFTER_SIZE, will flush binary logs.
  if [ $(stat -c%s ${LOG_DIR}/${binlog}) -gt ${FLUSH_BINLOG_AFTER_SIZE} ]; then
     DP_log "flush binary logs"
     ${MYSQL_CMD} -e "flush binary logs";
     global_last_flush_logs_time=${curr_time}
     return
  fi
  local diff_time=$((${curr_time}-${global_last_flush_logs_time}))
  if [[ ${diff_time} -lt ${global_flush_bin_logs_interval} ]]; then
     return
  fi
  local LATEST_TRANS=$(mysqlbinlog ${LOG_DIR}/${binlog} |grep 'Xid =' |head -n 1)
  # only flush bin logs when Xid exists
  if [[ -n "${LATEST_TRANS}" ]]; then
    DP_log "flush binary logs"
    ${MYSQL_CMD} -e "flush binary logs";
  fi
  global_last_flush_logs_time=${curr_time}
}

# upload bin logs by walg
function upload_bin_logs() {
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH/${DP_TARGET_POD_NAME}"
    global_latest_bin_log=$(ls -Ftr ${LOG_DIR}/|grep -e "^${LOG_PREFIX}.*[[:digit:]]$"|tail -n 1)
    if [ ! -z ${global_latest_bin_log} ];then
       global_latest_bin_log="${LOG_DIR}/${global_latest_bin_log}"
    fi
    wal-g binlog-push;
}

# get binlog start time
function get_binlog_start_time() {
  local binlog="${1:?missing binlog name}"
  local time=$(mysqlbinlog ${binlog} | grep -m 1 "end_log_pos" | awk '{print $1, $2}'|tr -d '#')
  local time=$(date -d "$time" -u '+%Y-%m-%dT%H:%M:%SZ')
  echo $time
}

# pull binlog and decompress
function pull_binlog() {
    file="${1:?missing file name}"
    fileName=$(basename ${file})
    datasafed pull ${file} ${fileName}
    zstd -d --rm ${fileName}
}

# get the start time for backup.status.timeRange
function get_start_time_for_range() {
   local oldest_bin_log=$(datasafed list -f --recursive / -o json | jq -s -r '.[] | sort_by(.mtime) | .[] | .path' | grep .zst | head -n 1)
   if [ ! -z ${oldest_bin_log} ]; then
     START_TIME=$(DP_analyze_start_time_from_datasafed "${oldest_bin_log}" get_binlog_start_time pull_binlog)
     echo ${START_TIME}
   fi
}

# save backup status info to sync file
function save_backup_status() {
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
  local TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
  # if no size changes, return
  if [[ ${TOTAL_SIZE} == ${global_old_size} ]];then
     return
  fi
  global_old_size=${TOTAL_SIZE}
  local START_TIME=$(get_start_time_for_range)
  local STOP_TIME=$(get_binlog_start_time ${global_latest_bin_log})
  DP_save_backup_status_info "${TOTAL_SIZE}" "${START_TIME}" "${STOP_TIME}"
}

# trap term signal
trap "echo 'Terminating...' && sync && exit 0" TERM
DP_log "start to archive binlog"
while true; do
  # check if mysql process is ok
  check_mysql_process

  # flush bin logs
  flush_binlogs

  # upload bin log
  upload_bin_logs

  # save backup status which will be updated to `backup` CR by the sidecar
  save_backup_status

  # purge the expired bin logs
  purge_expired_files
  sleep ${BINLOG_ARCHIVE_INTERVAL}
done