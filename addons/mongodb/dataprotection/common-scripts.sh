#!/bin/bash
function handle_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}
# log info file
function DP_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} INFO: $msg"
}

# log error info
function DP_error_log() {
    msg=$1
    local curr_date=$(date -u '+%Y-%m-%d %H:%M:%S')
    echo "${curr_date} ERROR: $msg"
}

function buildJsonString() {
    local jsonString=${1}
    local key=${2}
    local value=${3}
    if [ ! -z "$jsonString" ];then
       jsonString="${jsonString},"
    fi
    echo "${jsonString}\"${key}\":\"${value}\""
}

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
function DP_save_backup_status_info() {
    export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
    export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
  
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

function getToolConfigValue() {
  local var=$1
  cat "$toolConfig" | grep "$var" | awk '{print $NF}'
}

function set_backup_config_env() {
  toolConfig=/etc/datasafed/datasafed.conf
  if [ ! -f ${toolConfig} ]; then
    DP_error_log "Config file not found: ${toolConfig}"
    exit 1
  fi

  local provider=""
  local access_key_id=""
  local secret_access_key=""
  local region=""
  local endpoint=""
  local bucket=""

  IFS=$'\n'
  for line in $(cat ${toolConfig}); do
    line=$(eval echo $line)
    if [[ $line == "access_key_id"* ]]; then
      access_key_id=$(getToolConfigValue "$line")
    elif [[ $line == "secret_access_key"* ]]; then
      secret_access_key=$(getToolConfigValue "$line")
    elif [[ $line == "region"* ]]; then
      region=$(getToolConfigValue "$line")
    elif [[ $line == "endpoint"* ]]; then
      endpoint=$(getToolConfigValue "$line")
    elif [[ $line == "root"* ]]; then
      bucket=$(getToolConfigValue "$line")
    elif [[ $line == "provider"* ]]; then
      provider=$(getToolConfigValue "$line")
    fi
  done

  if [[ ! $endpoint =~ ^https?:// ]]; then
    endpoint="https://${endpoint}"
  fi

  if [[ "$provider" == "Alibaba" ]]; then
    regex='https?:\/\/oss-(.*?)\.aliyuncs\.com'
    if [[ "$endpoint" =~ $regex ]]; then
      region="${BASH_REMATCH[1]}"
      DP_log "Extract region from $endpoint-> $region"
    else
      DP_log "Failed to extract region from endpoint: $endpoint"
    fi
  elif [[ "$provider" == "TencentCOS" ]]; then
    regex='https?:\/\/cos\.(.*?)\.myqcloud\.com'
    if [[ "$endpoint" =~ $regex ]]; then
      region="${BASH_REMATCH[1]}"
      DP_log "Extract region from $endpoint-> $region"
    else
      DP_log "Failed to extract region from endpoint: $endpoint"
    fi
  elif [[ "$provider" == "Minio" ]]; then
    export S3_FORCE_PATH_STYLE="true"
  else
    echo "Unsupported provider: $provider"
  fi
  backup_path=$(dirname "$DP_BACKUP_BASE_PATH")

  export S3_ACCESS_KEY="${access_key_id}"
  export S3_SECRET_KEY="${secret_access_key}"
  export S3_REGION="${region}"
  export S3_ENDPOINT="${endpoint}"
  export S3_BUCKET="${bucket}"
  export S3_PREFIX="${backup_path#/}/$PBM_BACKUP_DIR_NAME"
  
  DP_log "storage config have been extracted."
}

# config backup agent
generate_endpoints() {
    local fqdns=$1
    local port=$2

    if [ -z "$fqdns" ]; then
        echo "ERROR: No FQDNs provided for config server endpoints." >&2
        exit 1
    fi

    IFS=',' read -ra fqdn_array <<< "$fqdns"
    local endpoints=()

    for fqdn in "${fqdn_array[@]}"; do
        trimmed_fqdn=$(echo "$fqdn" | xargs)
        if [[ -n "$trimmed_fqdn" ]]; then
            endpoints+=("${trimmed_fqdn}:${port}")
        fi
    done

    IFS=','; echo "${endpoints[*]}"
}

function export_pbm_env_vars() {
  # Get the cluster admin credentials from environment variables
  # CLUSTER_ADMIN_USER=""
  # CLUSTER_ADMIN_PASSWORD=""
  # for env_var in $(env | grep -E '^MONGODB_ADMIN_USER'); do
  #     CLUSTER_ADMIN_USER="${env_var#*=}"
  #     if [ -z "$CLUSTER_ADMIN_USER" ]; then
  #         continue
  #     fi
  #     break
  # done
  # for env_var in $(env | grep -E '^MONGODB_ADMIN_PASSWORD'); do
  #     CLUSTER_ADMIN_PASSWORD="${env_var#*=}"
  #     if [ -z "$CLUSTER_ADMIN_PASSWORD" ]; then
  #         continue
  #     fi
  #     break
  # done

  # if [ -z "$CLUSTER_ADMIN_USER" ] || [ -z "$CLUSTER_ADMIN_PASSWORD" ]; then
  #     echo "ERROR: MONGODB_ADMIN_USER or MONGODB_ADMIN_PASSWORD is not set." >&2
  #     exit 1
  # fi

  # export PBM_AGENT_MONGODB_USERNAME="$CLUSTER_ADMIN_USER"
  # export PBM_AGENT_MONGODB_PASSWORD="$CLUSTER_ADMIN_PASSWORD"

  export PBM_AGENT_MONGODB_USERNAME="$MONGODB_USER"
  export PBM_AGENT_MONGODB_PASSWORD="$MONGODB_PASSWORD"
  
  cfg_server_endpoints="$(generate_endpoints "$CFG_SERVER_POD_FQDN_LIST" "$CFG_SERVER_INTERNAL_PORT")"
  export PBM_MONGODB_URI="mongodb://$PBM_AGENT_MONGODB_USERNAME:$PBM_AGENT_MONGODB_PASSWORD@$cfg_server_endpoints/?authSource=admin&replSetName=$CFG_SERVER_REPLICA_SET_NAME"
}

function export_pbm_env_vars_for_rs() {
  export PBM_AGENT_MONGODB_USERNAME="$MONGODB_USER"
  export PBM_AGENT_MONGODB_PASSWORD="$MONGODB_PASSWORD"

  mongodb_endpoints="$(generate_endpoints "$MONGODB_POD_FQDN_LIST" "$KB_SERVICE_PORT")"
  export PBM_MONGODB_URI="mongodb://$PBM_AGENT_MONGODB_USERNAME:$PBM_AGENT_MONGODB_PASSWORD@$mongodb_endpoints/?authSource=admin&replSetName=$MONGODB_REPLICA_SET_NAME"
}

function sync_pbm_storage_config() {
  echo "INFO: Checking if PBM storage config exists"
  pbm_config_exists=true
  check_config=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json) || {
    pbm_config_exists=false
    echo "INFO: PBM storage config does not exist."
  }
  if [ "$pbm_config_exists" = "true" ]; then
    # check_config=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json)
    current_endpoint=$(echo "$check_config" | jq -r '.storage.s3.endpointUrl')
    current_region=$(echo "$check_config" | jq -r '.storage.s3.region')
    current_bucket=$(echo "$check_config" | jq -r '.storage.s3.bucket')
    current_prefix=$(echo "$check_config" | jq -r '.storage.s3.prefix')
    echo "INFO: Current PBM storage endpoint: $current_endpoint"
    echo "INFO: Current PBM storage region: $current_region"
    echo "INFO: Current PBM storage bucket: $current_bucket"
    echo "INFO: Current PBM storage prefix: $current_prefix"
    if [ "$current_prefix" = "$S3_PREFIX" ] && [ "$current_region" = "$S3_REGION" ] && [ "$current_bucket" = "$S3_BUCKET" ] && [ "$current_endpoint" = "$S3_ENDPOINT" ]; then
      echo "INFO: PBM storage config already exists."
    else
      pbm_config_exists=false
    fi
  fi
  if [ "$pbm_config_exists" = "false" ]; then
    cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin > /dev/null
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${S3_PREFIX}
    endpointUrl: ${S3_ENDPOINT}
    forcePathStyle: ${S3_FORCE_PATH_STYLE:-false}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
EOF
    echo "INFO: PBM storage configuration completed."
  fi
}

function print_pbm_logs_by_event() {
  local pbm_event=$1
  # echo "INFO: Printing PBM logs by event: $pbm_event"
  local pbm_logs=$(pbm logs -e $pbm_event --tail 200 --mongodb-uri "$PBM_MONGODB_URI" > /dev/null)
  local purged_logs=$(echo "$pbm_logs" | awk -v start="$PBM_LOGS_START_TIME" '$1 >= start')
  if [ -z "$purged_logs" ]; then
    return
  fi
  echo "$purged_logs"
  # echo "INFO: PBM logs by event: $pbm_event printed."
}

function print_pbm_tail_logs() {
  echo "INFO: Printing PBM tail logs"
  pbm logs --tail 20 --mongodb-uri "$PBM_MONGODB_URI"
}


function wait_for_other_operations() {
  status_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json) || {
    echo "INFO: PBM is not configured."
    return
  }
  local running_status=$(echo "$status_result" | jq -r '.running')
  local retry_count=0
  local max_retries=60
  while [ -n "$running_status" ] && [ "$running_status" != "{}" ] && [ $retry_count -lt $max_retries ]; do
    retry_count=$((retry_count+1))
    echo "INFO: Other operation $(echo "$running_status" | jq -r '.type') are running, waiting... ($retry_count/$max_retries)"
    sleep 5
    running_status=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.running')
  done
  if [ $retry_count -ge $max_retries ]; then
    echo "ERROR: Other operations are still running after $max_retries retries"
    exit 1
  fi
}

function export_logs_start_time_env() {
  local logs_start_time=$(date +"%Y-%m-%dT%H:%M:%SZ")
  export PBM_LOGS_START_TIME="${logs_start_time}"
}

function sync_pbm_config_from_storage() {
  echo "INFO: Syncing PBM config from storage..."
  pbm config --force-resync --mongodb-uri "$PBM_MONGODB_URI"
  print_pbm_logs_by_event "resync"
  
  # resync wait flag might don't work
  wait_for_other_operations

  echo "INFO: PBM config synced from storage."
}

function create_restore_signal() {
    phase=$1
    kubectl apply -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: $dp_cm_name
  namespace: $dp_cm_namespace
  labels:
    app.kubernetes.io/instance: $KB_CLUSTER_NAME
    apps.kubeblocks.io/restore-mongodb-shard: $phase
EOF
}

function process_restore_start_signal() {
    echo "INFO: Waiting for prepare restore start signal..."
    dp_cm_name="$KB_CLUSTER_NAME-restore-signal"
    dp_cm_namespace="$KB_NAMESPACE"
    while true; do
        set +e
        kubectl_get_result=$(kubectl get configmap $dp_cm_name -n $dp_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        set -e
        # Wait for the restore signal ConfigMap to be created or updated
        if [[ "$kubectl_get_exit_code" -ne 0 ]]; then
            if [[ "$kubectl_get_result" == *"not found"* ]]; then
                create_restore_signal "start"
            fi
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            if [[ "$annotation_value" == "start" ]]; then
                break
            elif [[ "$annotation_value" == "end" ]]; then
                echo "INFO: Restore completed, exiting."
                exit 0
            else
                echo "INFO: Restore start signal is $annotation_value, updating..."
                create_restore_signal "start"
            fi
        fi
        sleep 1
    done
    sleep 5
    echo "INFO: Prepare restore start signal completed."
}

function process_restore_end_signal() {
    echo "INFO: Waiting for prepare restore end signal..."
    sleep 5
    dp_cm_name="$KB_CLUSTER_NAME-restore-signal"
    dp_cm_namespace="$KB_NAMESPACE"
    while true; do
        set +e
        kubectl_get_result=$(kubectl get configmap $dp_cm_name -n $dp_cm_namespace -o json 2>&1)
        kubectl_get_exit_code=$?
        set -e
        # Wait for the restore signal ConfigMap to be created or updated
        if [[ "$kubectl_get_exit_code" -ne 0 ]]; then
            if [[ "$kubectl_get_result" == *"not found"* ]]; then
                create_restore_signal "end"
            fi
        else
            annotation_value=$(echo "$kubectl_get_result" | jq -r '.metadata.labels["apps.kubeblocks.io/restore-mongodb-shard"] // empty')
            if [[ "$annotation_value" == "end" ]]; then
                break
            else
                echo "INFO: Restore end signal is $annotation_value, updating..."
                create_restore_signal "end"
            fi
        fi
        sleep 1
    done
    echo "INFO: Prepare restore end signal completed."
}
