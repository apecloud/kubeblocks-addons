#!/bin/bash
# export wal-g environments
if [ ! -z "${MYSQL_ADMIN_PASSWORD}" ]; then
  DP_DB_PASSWORD=${MYSQL_ADMIN_PASSWORD}
  DP_DB_USER=${MYSQL_ADMIN_USER}
fi
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
MYSQL_CMD_WITH_COL="mysql -u ${DP_DB_USER} -h ${DP_DB_HOST}"
log_bin_basename=$(${MYSQL_CMD} -e "SHOW VARIABLES LIKE 'log_bin_basename';" | awk -F'\t' '{print $2}')
if [ -z "${log_bin_basename}" ]; then
   echo "ERROR: pod/${DP_TARGET_POD_NAME} connect failed."
   exit 1
fi
LOG_DIR=$(dirname "$log_bin_basename")
LOG_PREFIX=$(basename "$log_bin_basename")

global_latest_bin_log=""
global_last_flush_logs_time=$(date +%s)
global_last_purge_time=$(date +%s)
global_old_size=0
global_flush_bin_logs_interval=600

if [[ ${DP_ARCHIVE_INTERVAL} =~ ^[0-9]+s$ ]];then
  global_flush_bin_logs_interval=${DP_ARCHIVE_INTERVAL%s}
fi

global_backup_in_secondary=
if [ "${TARGET_POD_ROLE}" == "primary" ]; then
   global_backup_in_secondary=f
elif [ "${TARGET_POD_ROLE}" == "secondary" ]; then
   global_backup_in_secondary=t
fi

# checks if the mysql process is ok
function check_mysql_process() {
    is_ok=false
    sql="show slave status\G"
    slave_note="Slave_IO_Running: Yes"
    if [ "${USE_REPLICA_STATUS}" == "true" ]; then
       sql="show replica status\G"
       slave_note="Replica_IO_Running: Yes"
    fi
    for ((i=1;i<4;i++));do
      is_secondary=$(${MYSQL_CMD_WITH_COL} -e "${sql}" 2>/dev/null | grep "${slave_note}" &>/dev/null && echo "t" || echo "f")
      if [[ $? -eq 0  && (-z ${TARGET_POD_ROLE} || "${global_backup_in_secondary}" == "${is_secondary}") ]]; then
        is_ok=true
        break
      fi
      DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not OK, target role: ${TARGET_POD_ROLE}, is_secondary: ${is_secondary}, retry detection!"
      sleep 1
    done
    if [[ ${is_ok} == "false" ]];then
      DP_error_log "target backup pod/${DP_TARGET_POD_NAME} is not OK, target role: ${TARGET_POD_ROLE}, is_secondary: ${is_secondary}"
      exit 1
    fi
}

# clean up expired logfiles, interval is 60s
function purge_expired_files() {
  export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
  local currentUnix=$(date +%s)
  info=$(DP_purge_expired_files "${currentUnix}" "${global_last_purge_time}")
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
  if [ $(stat -c%s ${LOG_DIR}/${binlog}) -gt "${FLUSH_BINLOG_AFTER_SIZE}" ]; then
     DP_log "flush binary logs"
     ${MYSQL_CMD} -e "flush binary logs";
     global_last_flush_logs_time=${curr_time}
     return
  fi
  local diff_time=$((${curr_time}-${global_last_flush_logs_time}))
  if [[ ${diff_time} -lt ${global_flush_bin_logs_interval} ]]; then
     return
  fi
  local LATEST_TRANS=$(mysqlbinlog "${LOG_DIR}/${binlog}" |grep 'Xid =' |head -n 1)
  # only flush bin logs when Xid exists
  if [[ -n "${LATEST_TRANS}" ]]; then
    DP_log "flush binary logs"
    ${MYSQL_CMD} -e "flush binary logs";
  fi
  global_last_flush_logs_time=${curr_time}
}

# upload bin logs by walg
function upload_bin_logs() {
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
    global_latest_bin_log=$(ls -Ftr "${LOG_DIR}"/|grep -e "^${LOG_PREFIX}.*[[:digit:]]$"|tail -n 1)
    if [ ! -z "${global_latest_bin_log}" ];then
       global_latest_bin_log="${LOG_DIR}/${global_latest_bin_log}"
    fi
    wal-g binlog-push;
}

# get binlog start time
function get_binlog_start_time() {
  local binlog="${1:?missing binlog name}"
  local time=$(mysqlbinlog "${binlog}" | grep -m 1 "end_log_pos" | awk '{print $1, $2}'|tr -d '#')
  local time=$(date -d "$time" -u '+%Y-%m-%dT%H:%M:%SZ')
  echo $time
}

# pull binlog and decompress
function pull_binlog() {
    file="${1:?missing file name}"
    fileName=$(basename "${file}")
    datasafed pull "${file}" "${fileName}"
    zstd -d --rm "${fileName}"
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

cleanup_mysql_binlogs() {

    # Discover replica hosts from the target primary itself: each replica
    # registers its report_host there. The previous KB_ITS_*_HOSTNAME env
    # discovery never worked in a DataProtection job pod (those env vars were
    # only injected into workload pods by pre-1.0 KubeBlocks), which made this
    # whole cleanup a silent no-op.
    function get_replica_hosts() {
        local hosts
        hosts=$(mysql -u"${DP_DB_USER}" -h"${DP_DB_HOST}" -p"${DP_DB_PASSWORD}" -N -e "SHOW REPLICAS" 2>/dev/null | awk '{print $2}')
        if [[ -z "$hosts" ]]; then
            # MySQL 5.7 syntax
            hosts=$(mysql -u"${DP_DB_USER}" -h"${DP_DB_HOST}" -p"${DP_DB_PASSWORD}" -N -e "SHOW SLAVE HOSTS" 2>/dev/null | awk '{print $2}')
        fi
        printf '%s\n' "$hosts" | sed '/^$/d' | grep -v "^${DP_DB_HOST}$" || true
    }

    # Get synced binlog files from all replicas
    function get_synced_binlogs() {

        readarray -t all_binlogs < <(ls -1 "$LOG_DIR"/*-bin.[0-9]* | sort -V)

        local REPLICA_HOSTS=($(get_replica_hosts))

        # Check synchronization status of each replica
        for host in "${REPLICA_HOSTS[@]}"; do
            local status_output=$(
                mysql -u"${DP_DB_USER}" -h"$host" -p"${DP_DB_PASSWORD}" -N -e "SHOW REPLICA STATUS\G" 2>/dev/null ||
                mysql -u"${DP_DB_USER}" -h"$host" -p"${DP_DB_PASSWORD}" -N -e "SHOW SLAVE STATUS\G"
            )
            local current_file=$(echo "$status_output" | grep -o "${DP_TARGET_POD_NAME}-bin\.[0-9]*" | tail -n1)

            if [[ -z "$current_file" ]]; then
                return 1
            fi

            if [[ -z "$min_synced_file" ]] || [[ "$current_file" < "$min_synced_file" ]]; then
                min_synced_file="$current_file"
            fi
        done

        if [[ -z "$min_synced_file" ]]; then
            return 1
        fi

        local result_files=""
        for binlog in "${all_binlogs[@]}"; do
            local basename_binlog=$(basename "$binlog")
            if [[ "$basename_binlog" > "$min_synced_file" || "$basename_binlog" == "$min_synced_file" ]]; then
                break
            fi
            result_files="$result_files $basename_binlog"
        done

        echo "${result_files# }"
    }

    # Get the list of binlog files that have been uploaded to backup storage
    function get_uploaded_binlogs() {
        datasafed list -f --recursive / -o json \
            | jq -s -r ".[] | sort_by(.mtime) | .[] | .path" \
            | grep "\.zst$" \
            | grep "${DP_TARGET_POD_NAME}" \
            | xargs -I {} basename {} .zst \
            | paste -sd ' ' -
    }

    # Clean up old binlog files at master node that have been both synced and uploaded
    function purge_master_binlogs() {
      local synced_files="$1"
      local uploaded_files="$2"

      # Get all binlog files sorted by sequence number
      local all_binlogs=($(ls -1 "$LOG_DIR"/*[!.index] | sort -V))
      local total_files=${#all_binlogs[@]}

      # If total files <= 5, no need to purge
      if [[ $total_files -le 5 ]]; then
          echo "Only $total_files binlog files, no need to purge"
          return
      fi

      # PURGE BINARY LOGS TO '<file>' deletes every file BEFORE <file> (prefix
      # deletion). So the scan must stop at the FIRST file that has to be kept
      # (not synced+uploaded, or one of the newest 5): purging past it would
      # delete it as well and tear a hole in the archived binlog sequence.
      local keep_tail_start=$((total_files - 5))
      local first_kept=""
      local i
      for ((i = 0; i < total_files; i++)); do
          local base_name=$(basename "${all_binlogs[$i]}")
          if ((i >= keep_tail_start)); then
              first_kept="$base_name"
              echo "Keeping $base_name and newer (newest 5 binlog files)"
              break
          fi
          if ! (echo "$synced_files" | tr ' ' '\n' | grep -Fxq "$base_name" &&
                echo "$uploaded_files" | tr ' ' '\n' | grep -Fxq "$base_name"); then
              first_kept="$base_name"
              echo "Keeping $base_name and newer (not yet synced or uploaded)"
              break
          fi
      done

      if [[ -z "$first_kept" || "$first_kept" == "$(basename "${all_binlogs[0]}")" ]]; then
          echo "No purgeable binlog prefix on master host"
          return
      fi

      echo "Purging binary logs before $first_kept on master host"
      if mysql -u"${DP_DB_USER}" -h"${DP_DB_HOST}" -p"${DP_DB_PASSWORD}" -N -e \
          "PURGE BINARY LOGS TO '$first_kept'" &>/dev/null; then
          echo "Successfully purged binary logs before $first_kept on master host ${DP_DB_HOST}"
      else
          echo "Failed to connect or purge binary logs on master host ${DP_DB_HOST}"
      fi
    }

    # Purge all binlog files on replica except for the latest 5 files
    function purge_replica_binlogs() {
        local REPLICA_HOSTS=($(get_replica_hosts))

        for host in "${REPLICA_HOSTS[@]}"; do
            echo "Processing replica host: $host"

            # Get all binlog files on this replica, sorted by sequence number
            local binlog_files=$(mysql -u"${DP_DB_USER}" -h"$host" -p"${DP_DB_PASSWORD}" -N -e \
                "SHOW BINARY LOGS" 2>/dev/null | awk '{print $1}' | sort -V)

            if [[ -z "$binlog_files" ]]; then
                echo "Failed to get binary logs from replica host $host, skipping..."
                continue
            fi

            # Count total number of binlog files
            local total_files=$(echo "$binlog_files" | wc -l)

            # If total files <= 5, no need to purge
            if [[ $total_files -le 5 ]]; then
                echo "Only $total_files binlog files on $host, no need to purge"
                continue
            fi

            # Get the target binlog (files to keep are after this one)
            local files_to_delete=$((total_files - 4))
            local target_binlog=$(echo "$binlog_files" | head -n $files_to_delete | tail -n 1)

            # Execute PURGE BINARY LOGS command
            if mysql -u"${DP_DB_USER}" -h"$host" -p"${DP_DB_PASSWORD}" -N -e \
                "PURGE BINARY LOGS TO '$target_binlog'" &>/dev/null; then
                echo "Successfully purged binary logs up to $target_binlog on replica host $host"
            else
                echo "Failed to connect or purge binary logs on replica host $host"
            fi
        done
    }

    # Get list of synced binlogs
    local synced_binlogs=$(get_synced_binlogs)
    if [ $? -ne 0 ] || [ -z "$synced_binlogs" ]; then
        echo "No synced binlog files found"
        return 0
    fi

    # Get list of uploaded binlogs
    local uploaded_binlogs=$(get_uploaded_binlogs)
    if [ -z "$uploaded_binlogs" ]; then
        echo "No uploaded binlog files found"
        return 0
    fi

    # Execute cleanup process
    purge_master_binlogs "$synced_binlogs" "$uploaded_binlogs"
    purge_replica_binlogs
}

# trap term signal
trap "echo 'Terminating...' && sync && exit 0" TERM
DP_log "start to archive binlog"
if [ -f "${VOLUME_DATA_DIR}/binlog.000004" ]; then
   # will create a binlog.000004 after hscale by xtrabckup.
   cp ${VOLUME_DATA_DIR}/binlog.000004 ${VOLUME_DATA_DIR}/binlog/binlog.000004
fi
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

  # clean up synced and uploaded binary log files when disk usage reaches the
  # threshold. The threshold defaults to 80% (production behaviour unchanged);
  # it is overridable via PURGE_BINLOG_DISK_THRESHOLD so tests can exercise the
  # purge path without filling a large shared host volume to 80%.
  purge_threshold="${PURGE_BINLOG_DISK_THRESHOLD:-80}"
  disk_usage=$(df -h ${LOG_DIR} | awk 'NR==2 {print $5}' | cut -d'%' -f1)
  if [ -n "${disk_usage}" ] && [ "${disk_usage}" -ge "${purge_threshold}" ] && [ "${PURGE_BINLOG}" = "on" ]; then
      echo "Executing cleanup_mysql_binlogs due to: Disk usage is ${disk_usage}% (>= ${purge_threshold}%)"
      cleanup_mysql_binlogs
  fi

  sleep "${BINLOG_ARCHIVE_INTERVAL}"
done