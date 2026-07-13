#!/bin/bash
# shellcheck disable=SC2086

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
        echo "ERROR: No FQDNs provided for endpoints." >&2
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

function write_pbm_storage_config_file() {
  local file=$1
  if [ -z "$file" ]; then
    echo "ERROR: PBM storage config file path is empty"
    exit 1
  fi
  mkdir -p "$(dirname "$file")"
  cat > "$file" <<EOF
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
restore:
  numDownloadWorkers: ${PBM_RESTORE_DOWNLOAD_WORKERS:-4}
backup:
  timeouts:
    startingStatus: 60
EOF
}

function target_syncer_host() {
  if [ -n "${DP_DB_HOST:-}" ] && [ -z "${DP_TARGET_POD_NAME:-}" ]; then
    echo "$DP_DB_HOST"
    return
  fi

  local pod_name="${DP_TARGET_POD_NAME:-${POD_NAME:-}}"
  local component_name="${CLUSTER_COMPONENT_NAME:-${KB_CLUSTER_COMP_NAME:-}}"
  local namespace="${CLUSTER_NAMESPACE:-${KB_NAMESPACE:-${POD_NAMESPACE:-}}}"
  local cluster_domain="${KUBERNETES_CLUSTER_DOMAIN:-cluster.local}"
  if [ -z "$pod_name" ] || [ -z "$component_name" ] || [ -z "$namespace" ]; then
    echo "ERROR: Cannot build target syncer host, pod=$pod_name component=$component_name namespace=$namespace" >&2
    exit 1
  fi
  echo "${pod_name}.${component_name}-headless.${namespace}.svc.${cluster_domain}"
}

function syncerctl_cmd() {
  local host
  host=$(target_syncer_host)
  local port="${SYNCER_SERVICE_PORT:-3601}"
  syncerctl --host "$host" --port "$port" "$@"
}

function configure_syncer_backup() {
  local cnf_file="${MOUNT_DIR:-/tmp}/tmp/pbm_syncer_storage.yaml"
  write_pbm_storage_config_file "$cnf_file"
  echo "INFO: Configuring PBM storage through syncer on $(target_syncer_host)..."
  syncerctl_cmd backup configure --file "$cnf_file"
}

function prepare_restore_storage_config() {
  RESTORE_STORAGE_CONFIG_FILE="${MOUNT_DIR:-/tmp}/tmp/pbm_restore_syncer_storage.yaml"
  write_pbm_storage_config_file "$RESTORE_STORAGE_CONFIG_FILE"
  export RESTORE_STORAGE_CONFIG_FILE
}

function wait_for_syncer_backup_completion() {
  local backup_name=$1
  local max_retries=${SYNCER_PBM_WAIT_MAX_RETRIES:-720}
  local retry_interval=${SYNCER_PBM_WAIT_INTERVAL_SECONDS:-5}
  local attempt=0
  describe_result=""
  while true; do
    describe_result=$(syncerctl_cmd backup status --op-id "$backup_name")
    local found
    local status
    found=$(echo "$describe_result" | jq -r '.found // false')
    status=$(echo "$describe_result" | jq -r '.status // empty')
    echo "INFO: Backup $backup_name status: found=$found status=$status"
    if [ "$found" = "true" ] && [ "$status" = "done" ]; then
      return 0
    fi
    if [ "$status" = "error" ] || [ "$status" = "failed" ]; then
      echo "ERROR: Backup $backup_name failed: $(echo "$describe_result" | jq -r '.error // empty')"
      exit 1
    fi
    attempt=$((attempt+1))
    if [ $attempt -gt $max_retries ]; then
      echo "ERROR: Backup $backup_name did not complete after $max_retries retries"
      exit 1
    fi
    sleep "$retry_interval"
  done
}

function wait_for_syncer_restore_completion() {
  local request_id=$1
  local max_retries=${SYNCER_RESTORE_WAIT_MAX_RETRIES:-7200}
  local retry_interval=${SYNCER_RESTORE_WAIT_INTERVAL_SECONDS:-1}
  local attempt=0
  local last_phase=""
  if [ -z "$request_id" ]; then
    echo "ERROR: Syncer restore start did not return request_id."
    exit 1
  fi
  while true; do
    local restore_status
    set +e
    restore_status=$(syncerctl_cmd restore status --request-id "$request_id" 2>&1)
    local status_exit=$?
    set -e
    if [ $status_exit -eq 0 ]; then
      local status
      local phase
      status=$(echo "$restore_status" | jq -r '.status // empty')
      phase=$(echo "$restore_status" | jq -r '.phase // empty')
      if [ -n "$phase" ] && [ "$phase" != "$last_phase" ]; then
        echo "INFO: Restore request $request_id phase=$phase"
        last_phase="$phase"
      fi
      if [ "$status" = "done" ]; then
        return 0
      fi
      if [ "$status" = "failed" ] || [ "$status" = "error" ]; then
        echo "ERROR: Syncer restore failed: $(echo "$restore_status" | jq -r '.error // empty')"
        exit 1
      fi
    else
      echo "INFO: Waiting for syncer restore status: $restore_status"
    fi
    attempt=$((attempt+1))
    if [ $attempt -gt $max_retries ]; then
      echo "ERROR: Restore request $request_id did not complete after $max_retries retries"
      exit 1
    fi
    sleep "$retry_interval"
  done
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
restore:
  numDownloadWorkers: ${PBM_RESTORE_DOWNLOAD_WORKERS:-4}
backup:
  timeouts:
    startingStatus: 60
EOF
    sleep 5
    echo "INFO: PBM storage configuration completed."
  fi
}

function print_pbm_tail_logs() {
  echo "INFO: Printing PBM tail logs"
  pbm logs --tail 20 --mongodb-uri "$PBM_MONGODB_URI"
}

function handle_backup_exit() {
  exit_code=$?
  set +e
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

function handle_restore_exit() {
  exit_code=$?
  set +e
  if [ -n "${RESTORE_STORAGE_CONFIG_FILE:-}" ]; then
    rm -f "$RESTORE_STORAGE_CONFIG_FILE"
  fi
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    exit 1
  fi
}

function handle_pitr_exit() {
  exit_code=$?
  set +e
  if [ $exit_code -ne 0 ]; then
    print_pbm_tail_logs

    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

function wait_for_other_operations() {
  status_result=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json) || {
    echo "INFO: PBM is not configured."
    return
  }
  local except_type=$1
  local running_status=$(echo "$status_result" | jq -r '.running')
  local retry_count=0
  local max_retries=60
  while [ -n "$running_status" ] && [ "$running_status" != "{}" ] && [ $retry_count -lt $max_retries ]; do
    retry_count=$((retry_count+1))
    local running_type=$(echo "$running_status" | jq -r '.type')
    if [ -n "$running_type" ] && [ "$running_type" = "$except_type" ]; then
      break
    fi
    echo "INFO: Other operation $running_type is running, waiting... ($retry_count/$max_retries)"
    sleep 5
    running_status=$(pbm status --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.running')
  done
  if [ $retry_count -ge $max_retries ]; then
    echo "ERROR: Other operations are still running after $max_retries retries"
    exit 1
  fi
}

function sync_pbm_config_from_storage() {
  echo "INFO: Syncing PBM config from storage..."

  wait_for_other_operations

  pbm config --force-resync --mongodb-uri "$PBM_MONGODB_URI"
  # resync wait flag might don't work
  wait_for_other_operations

  echo "INFO: PBM config synced from storage."
}

function get_describe_backup_info() {
  describe_result=""
  local max_retries=60
  local retry_interval=5
  local attempt=1
  set +e
  while [ $attempt -le $max_retries ]; do
      describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json 2>&1)
      if [ $? -eq 0 ] && [ -n "$describe_result" ]; then
          break
      elif echo "$describe_result" | grep -q "not found"; then
          echo "INFO: Attempt $attempt: backup $backup_name not found, retrying in ${retry_interval}s..."
          if [ $((attempt % 30)) -eq 29 ]; then
              echo "INFO: Sync PBM config from storage again."
              sync_pbm_config_from_storage
          fi
          sleep $retry_interval
          ((attempt++))
          continue
      else
          echo "ERROR: Failed to get backup metadata: $describe_result"
          exit 1
      fi
  done
  set -e

  if [ -z "$describe_result" ] || echo "$describe_result" | grep -q "not found"; then
      echo "ERROR: Failed to get backup metadata after $max_retries attempts"
      exit 1
  fi
}
