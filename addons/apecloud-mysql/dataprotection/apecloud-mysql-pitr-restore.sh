#!/bin/bash
set -e;

# use datasafed and default config
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

baseBackupStartTimestamp=${DP_BASE_BACKUP_START_TIMESTAMP}
if [ -f $DATA_DIR/xtrabackup_info ]; then
  DP_BASE_BACKUP_START_TIME=$(cat $DATA_DIR/xtrabackup_info | grep start_time | awk -F ' = ' '{print $2}');
  baseBackupStartTimestamp=$(date -d"${DP_BASE_BACKUP_START_TIME}" +%s)
fi
log_index_name="archive_log.index"

function fetch_pitr_binlogs() {
    echo "INFO: fetch binlogs from ${DP_BASE_BACKUP_START_TIME}"
    for file in $(datasafed list -f --recursive --newer-than ${baseBackupStartTimestamp} / -o json | jq -s -r '.[] | sort_by(.mtime) | .[] | .path' | grep .zst);do
        file_without_zst=${file%.*}
        dir_path=`dirname ${file_without_zst}`
        # mkdir the log directory
        mkdir -p ${PITR_DIR}/${dir_path}
        datasafed pull ${file} - | zstd -d -o ${PITR_DIR}/${file_without_zst}
        echo "${PITR_RELATIVE_PATH}/${file_without_zst}" >> ${PITR_DIR}/${log_index_name}
        # check if the binlog file contains the data for recovery time
        log_start_time=$(mysqlbinlog ${PITR_DIR}/${file_without_zst} | grep -m 1 "end_log_pos" | awk '{print $1, $2}'|tr -d '#')
        log_start_timestamp=$(date -d "${log_start_time}" +%s)
        if [[ ${log_start_timestamp} -gt ${DP_RESTORE_TIMESTAMP} ]];then
           DP_log "${file} out of range ${DP_RESTORE_TIME}"
           break
        fi
    done
}

function save_to_restore_file() {
    if [ -f ${DATA_DIR}/.xtrabackup_restore_new_cluster ];then
       restore_signal_file=${DATA_DIR}/.xtrabackup_restore_new_cluster
    else
       restore_signal_file=${DATA_DIR}/.restore_new_cluster
    fi
    echo "archive_log_index=${PITR_RELATIVE_PATH}/${log_index_name}" > ${restore_signal_file}
    kb_recover_time=$(date -d "${DP_RESTORE_TIME}" -u '+%Y-%m-%d %H:%M:%S')
    echo "recovery_target_datetime=${kb_recover_time}" >> ${restore_signal_file}
    sync
}

fetch_pitr_binlogs

if [ -f ${PITR_DIR}/${log_index_name} ];then
  save_to_restore_file
  DP_log "fetch binlog finished."
else
  DP_log "didn't get any binlogs."
fi