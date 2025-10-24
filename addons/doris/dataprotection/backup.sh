#!/bin/bash

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
        export DP_DORIS_REPOSITORY="APE_${cluster_name_fixed}"
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
    
    location+="/$CLUSTER_NAMESPACE/$KB_CLUSTER_NAME-$KB_CLUSTER_UID"
    export DP_S3_LOCATION="$location"
}

prepare_s3_repository() {
    empty_check "DP_DORIS_REPOSITORY"
    empty_check "DP_S3_LOCATION"
    
    DP_log "CHECK S3 REPOSITORY '$DP_DORIS_REPOSITORY' in DORIS "
    
    local repo_exists
    repo_exists=$($SQL_CMD "SHOW REPOSITORIES" | grep -c "$DP_DORIS_REPOSITORY")
    
    if [ "$repo_exists" -gt 0 ]; then
        DP_log "REPOSITORY '$DP_DORIS_REPOSITORY' is exists"
    else
        DP_log "REPOSITORY '$DP_DORIS_REPOSITORY' not exists, create it..."

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
            DP_log "Error: Failed to create repository '$DP_DORIS_REPOSITORY'"
        fi
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
    DP_log "Wait for backup tasks to complete in $max_wait_time seconds..."
    local all_dbs=$1
    DP_log "Backup databases: $all_dbs"

    local max_wait_time=3600  # 1h
    local wait_interval=10    # 10s
    local elapsed_time=0
    local all_finished=false
    
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

 


main() {
    start_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    parse_datasafed_conf
    prepare_s3_repository
    do_backup_and_wait
    end_time=$(date -u '+%Y-%m-%dT%H:%M:%SZ')
    DP_save_backup_status_info "0" "$start_time" "$end_time" "" ""
}

main