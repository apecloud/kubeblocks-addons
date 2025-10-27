#!/bin/bash

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

SQL_CMD="mysql -N -B -h ${DP_DB_HOST}.${POD_NAMESPACE}.svc.cluster.local -P ${FE_QUERY_PORT} -u root -p${DP_DB_PASSWORD} -e"

DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}

# log error info
DP_error_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} ERROR: $msg"
    exit 1
}

empty_check() {
    var_name=$1
    if [ -z "${!var_name}" ]; then
        DP_error_log "$var_name is empty"
    fi
}

parse_datasafed_conf() {
    local conf_file="/etc/datasafed/datasafed.conf"
    
    if [ ! -f "$conf_file" ]; then
        DP_error_log "s3 repository config file not found: $conf_file"
    fi
    
    
    local s3_type=""
    local s3_provider=""
    local s3_env_auth=""
    local s3_access_key_id=""
    local s3_secret_access_key=""
    local s3_region=""
    local s3_endpoint=""
    local s3_root=""
    local s3_no_check_certificate=""
    local s3_no_check_bucket=""
    local s3_chunk_size=""
    
    while IFS='=' read -r key value; do
        key=$(echo "$key" | xargs)
        value=$(echo "$value" | xargs)
        
        case "$key" in
            "type")
                s3_type="$value"
                ;;
            "provider")
                s3_provider="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
                ;;
            "env_auth")
                s3_env_auth="$value"
                ;;
            "access_key_id")
                s3_access_key_id="$value"
                ;;
            "secret_access_key")
                s3_secret_access_key="$value"
                ;;
            "region")
                s3_region="$value"
                ;;
            "endpoint")
                s3_endpoint=$(echo "$value" | tr -d '`"')
                ;;
            "root")
                s3_root="$value"
                ;;
            "no_check_certificate")
                s3_no_check_certificate="$value"
                ;;
            "no_check_bucket")
                s3_no_check_bucket="$value"
                ;;
            "chunk_size")
                s3_chunk_size="$value"
                ;;
        esac
    done < <(grep -v '^\[' "$conf_file" | grep '=')
    
    export DP_S3_TYPE="$s3_type"
    export DP_S3_PROVIDER="$s3_provider"
    export DP_S3_ENV_AUTH="$s3_env_auth"
    export DP_S3_ACCESS_KEY_ID="$s3_access_key_id"
    export DP_S3_SECRET_ACCESS_KEY="$s3_secret_access_key"
    export DP_S3_REGION="$s3_region"
    #
    export DP_S3_ENDPOINT="$s3_endpoint"
    export DP_S3_ROOT="$s3_root"
    export DP_S3_NO_CHECK_CERTIFICATE="$s3_no_check_certificate"
    export DP_S3_NO_CHECK_BUCKET="$s3_no_check_bucket"
    export DP_S3_CHUNK_SIZE="$s3_chunk_size"
    BACKUP_ID=$(echo "$DP_BACKUP_NAME" | awk -F'-' '{print $NF}')
    export DP_BACKUP_ID="$BACKUP_ID"
    empty_check "DP_S3_TYPE"
    empty_check "DP_S3_PROVIDER"
    empty_check "DP_S3_ACCESS_KEY_ID"
    empty_check "DP_S3_SECRET_ACCESS_KEY"
    empty_check "DP_S3_ENDPOINT"
    empty_check "DP_S3_ROOT"
    empty_check "DP_BACKUP_ID"

    # parse s3 repository name from endpoint
    if [ -n "$s3_endpoint" ]; then
        endpoint_without_protocol=${s3_endpoint#*://}
        host_part=${endpoint_without_protocol%%:*}
        host_part=${host_part%%/*}
        cluster_name=${host_part%%.*}
        # replace - with _
        cluster_name_fixed=${cluster_name//-/_}
        export DP_DORIS_REPOSITORY="${cluster_name_fixed}_${DP_BACKUP_ID}"
    fi
    prepare_repository_location

    DP_log "S3 PROVIDER: $DP_S3_PROVIDER"
    DP_log "S3 ENDPOINT: $DP_S3_ENDPOINT"
    DP_log "S3 ROOT: $DP_S3_ROOT"
    DP_log "DORIS REPOSITORY NAME: $DP_DORIS_REPOSITORY"
    DP_log "S3 LOCATION: $DP_S3_LOCATION"
    DP_log "BACKUP ID: $DP_BACKUP_ID"
}


prepare_repository_location() {
     local location=""
     if [[ "$DP_S3_ROOT" == s3://* ]]; then
        location="$DP_S3_ROOT"
    else
        location="s3://$DP_S3_ROOT"
    fi
    
    location+="$DP_BACKUP_BASE_PATH"
    export DP_S3_LOCATION="$location"
}

prepare_s3_repository() {
    empty_check "DP_DORIS_REPOSITORY"
    empty_check "DP_S3_LOCATION"
    local create_repo_sql="CREATE REPOSITORY \`$DP_DORIS_REPOSITORY\` "
    create_repo_sql+="WITH S3 "
    create_repo_sql+="ON LOCATION \"$DP_S3_LOCATION\" "
    create_repo_sql+="PROPERTIES ("
    create_repo_sql+="\"s3.endpoint\" = \"$DP_S3_ENDPOINT\", "
    create_repo_sql+="\"s3.access_key\" = \"$DP_S3_ACCESS_KEY_ID\", "
    create_repo_sql+="\"s3.secret_key\" = \"$DP_S3_SECRET_ACCESS_KEY\""
    
    if [ -n "$DP_S3_REGION" ]; then
        create_repo_sql+=", \"s3.region\" = \"$DP_S3_REGION\""
    fi

        # minio
    if [ "$DP_S3_PROVIDER" = "minio" ]; then
            create_repo_sql+=", \"s3.region\" = \"dummy-region\""
            create_repo_sql+=", \"use_path_style\" = \"true\""
    fi
        

    create_repo_sql+=");"
        
    DP_log "Try to create repository: $create_repo_sql"

    if ! $SQL_CMD "$create_repo_sql"; then
            DP_error_log "Failed to create repository: $DP_DORIS_REPOSITORY"
    fi
        
    repo_exists=$($SQL_CMD "SHOW REPOSITORIES" | grep -c "$DP_DORIS_REPOSITORY")
    if [ "$repo_exists" -gt 0 ]; then
        DP_log "Repository '$DP_DORIS_REPOSITORY' created successfully"
    else
        DP_error_log "Error: Failed to create repository '$DP_DORIS_REPOSITORY'"
    fi     
}

cleanup_repository() {
    empty_check "DP_DORIS_REPOSITORY"
    DP_log "Try to drop repository: $DP_DORIS_REPOSITORY"
    if ! $SQL_CMD "DROP REPOSITORY \`$DP_DORIS_REPOSITORY\`"; then
        DP_error_log "Failed to drop repository: $DP_DORIS_REPOSITORY"
    fi
    DP_log "Repository '$DP_DORIS_REPOSITORY' dropped successfully"
}

do_snapshot_restore(){
    snapshot_name=$1
    db_name=$(echo "$snapshot_name" | awk -F'_' '{print $1}')
}

restore_backups(){
    # show all snapshot
    local all_dbs=""
    $SQL_CMD "SHOW SNAPSHOT ON \`$DP_DORIS_REPOSITORY\`" | while read -r line; do
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
    done

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