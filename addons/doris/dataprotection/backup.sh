#!/bin/bash

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

SQL_CMD="mysql -N -B -h ${DP_DB_HOST}.${POD_NAMESPACE}.svc.cluster.local -P ${FE_QUERY_PORT} -u root -p${DP_DB_PASSWORD} -e"

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
DP_save_backup_status_info() {
    local totalSize=$1
    local startTime=$2
    local stopTime=$3
    local timeZone=$4
    local extras=$5
    local timeZoneStr=""
    if [ ! -z ${timeZone} ]; then
       timeZoneStr=",\"timeZone\":\"${timeZone}\""
    fi
    if [ -z "${stopTime}" ];then
      echo "{\"totalSize\":\"${totalSize}\"}" > ${DP_BACKUP_INFO_FILE}
    elif [ -z "${startTime}" ];then
      echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"end\":\"${stopTime}\"${timeZoneStr}}}" > ${DP_BACKUP_INFO_FILE}
    else
      echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"start\":\"${startTime}\",\"end\":\"${stopTime}\"${timeZoneStr}}}" > ${DP_BACKUP_INFO_FILE}
    fi
}

do_backup_and_wait() {
    all_dbs=$($SQL_CMD "SHOW DATABASES" | grep -v "information_schema" | grep -v "mysql")
    # DP_BACKUP_NAME=brier-5f7695dcfb-20251023071631    
    for db in $all_dbs; do
        $SQL_CMD "BACKUP SNAPSHOT $db.\`${db}_${DP_BACKUP_ID}\` TO $DP_DORIS_REPOSITORY" -D "$db"
    done

    wait_backup_complete "$all_dbs"
}

wait_backup_complete() {
    local max_wait_time=3600  # 1h
    local wait_interval=10    # 10s
    local elapsed_time=0
    local all_finished=false

    DP_log "Wait for backup tasks to complete in $max_wait_time seconds..."
    local all_dbs=$1
    DP_log "Backup databases: $all_dbs"
   
    while [ $elapsed_time -lt $max_wait_time ]; do
        all_finished=true
        
        for db in $all_dbs; do
            local backup_status
            DP_log "Check backup status for database $db"
            backup_status=$($SQL_CMD "SHOW BACKUP" -D "$db"  | grep "$db.$BACKUP_ID" | awk '{print $4}')            
            if [ -z "$backup_status" ]; then
                DP_log "Warning: no backup status found for database $db"
                all_finished=false
            elif [ "$backup_status" != "FINISHED" ]; then
                DP_log "Backup task for database $db is not finished, status: $backup_status"
                all_finished=false
            else
                DP_log "Backup task for database $db is finished"
            fi
        done
        
        if $all_finished; then
            DP_log "All backup tasks are finished"
            return
        fi
        
        DP_log "Wait $wait_interval seconds to check backup status again..."
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    DP_error_log "Error: Backup tasks timeout after $elapsed_time seconds"
}

backup_meta() {
   tar -cvf - /opt/apache-doris/fe/doris-meta | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst"
}

main() {
    start_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    parse_datasafed_conf
    prepare_s3_repository
    do_backup_and_wait
    cleanup_repository
    end_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    total_size=0
    for i in $(seq 1 5); do
        echo "Attempt ${i} to get backup total size..."
        output=$(datasafed stat / 2>&1)
        if echo "${output}" | grep -q 'TotalSize:'; then
            total_size=$(echo "${output}" | grep 'TotalSize:' | awk '{print $2}')
            if [[ -n "${total_size}" && "${total_size}" -gt 0 ]]; then
                echo "Successfully got total size: ${total_size}"
                break
            fi
        fi
        echo "Failed to get a valid total size. Full output: ${output}"
        sleep 2
    done
    total_size=$(datasafed stat / | grep 'TotalSize:' | awk '{print $2}')
    DP_save_backup_status_info "${total_size:-0}" "$start_time" "$end_time" "" ""
}

main