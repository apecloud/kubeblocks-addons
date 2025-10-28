#!/bin/bash

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

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