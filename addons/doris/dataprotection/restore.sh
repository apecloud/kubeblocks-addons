export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

SQL_CMD="mysql -N -B -h ${DP_DB_HOST}.${POD_NAMESPACE}.svc.cluster.local -P ${FE_QUERY_PORT} -u root -p${DP_DB_PASSWORD} -e"

do_snapshot_restore(){
    snapshot_name=$1
    db_name=$(echo "$snapshot_name" | awk -F'_' '{print $1}')
}

restore_backups(){
    # show all snapshot
    local all_dbs=""
    local all_snapshots=$($SQL_CMD "SHOW SNAPSHOT ON \`$DP_DORIS_REPOSITORY\`")

    while read -r line; do
        snapshot_name=$(echo "$line" | awk '{print $1}')
        timestamp=$(echo "$line" | awk '{print $2}')
        # ignore empty lines
        if [ -z "$snapshot_name" ]; then
            continue
        fi

        if [[ "$snapshot_name" != *_${DP_BACKUP_ID} ]]; then
            DP_log "Skipping snapshot '$snapshot_name' as it does not belong to this backup."
            continue
        fi

        if [[ "$snapshot_name" == "__internal_schema_"* ]]; then
            DP_log "Skipping internal schema snapshot: $snapshot_name"
            continue
        fi

        # Correctly parse db_name by removing the backup ID suffix
        db_name=${snapshot_name%_${DP_BACKUP_ID}}        
        DP_log "Creating database \`$db_name\` if not exists"
        $SQL_CMD "CREATE DATABASE IF NOT EXISTS \`$db_name\`"
        if [ $? -ne 0 ]; then
            DP_log "Failed to create database \`$db_name\`, skip restore snapshot \`$snapshot_name\`"
            continue
        fi
        local restore_sql
        restore_sql="RESTORE SNAPSHOT \`$snapshot_name\` FROM \`$DP_DORIS_REPOSITORY\`"
        restore_sql+=" PROPERTIES ("
        restore_sql+="\"backup_timestamp\" = \"$timestamp\""
        restore_sql+=");"
        DP_log "Restoring snapshot \`$snapshot_name\` for database \`$db_name\`: $restore_sql"
        if ! $SQL_CMD "$restore_sql" -D "$db_name"; then
            DP_error_log "Failed to restore snapshot \`$snapshot_name\` for database \`$db_name\`"
        fi
        all_dbs+="$db_name "
    done <<< "$all_snapshots"

    all_dbs=$(echo "$all_dbs" | xargs)
    wait_for_restore_complete "$all_dbs"
}

wait_for_restore_complete() {
    local max_wait_time=3600  # 1h
    local wait_interval=10    # 10s
    local elapsed_time=0
    local all_finished=false
    local all_dbs=$1
    DP_log "Wait for restore tasks to complete in $max_wait_time seconds..."
    DP_log "Restore databases: $all_dbs"

    while [ $elapsed_time -lt $max_wait_time ]; do
        all_finished=true        
        for db in $all_dbs; do
            local restore_status
            DP_log "Check restore status for database $db"
            restore_status=$($SQL_CMD "SHOW RESTORE" -D "$db"  | grep "$db.$BACKUP_ID" | awk '{print $5}')            
            if [ -z "$restore_status" ]; then
                DP_log "Warning: no restore status found for database $db"
                all_finished=false
            elif [ "$restore_status" != "FINISHED" ]; then
                DP_log "Restore task for database $db is not finished, status: $restore_status"
                all_finished=false
            else
                DP_log "Restore task for database $db is finished"
            fi
        done
        
        if $all_finished; then
            DP_log "All restore tasks are finished"
            return
        fi
        
        DP_log "Wait $wait_interval seconds to check restore status again..."
        sleep $wait_interval
        elapsed_time=$((elapsed_time + wait_interval))
    done
    
    DP_error_log "Error: Restore tasks timeout after $elapsed_time seconds"
}

main() {
    parse_datasafed_conf
    prepare_s3_repository
    restore_backups
    cleanup_repository
}

main