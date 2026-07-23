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

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
function DP_save_backup_status_info() {
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
  if [ -n "${DP_DB_HOST:-}" ]; then
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

function prepare_pbm_operation_storage_config() {
  local mount_dir="${MOUNT_DIR:-}"
  if [ -z "$mount_dir" ] || [[ "$mount_dir" != /* ]]; then
    echo "ERROR: MOUNT_DIR must be an absolute target PVC mount path"
    exit 1
  fi

  local input_dir="$mount_dir/tmp/pbm-restore-input"
  PBM_STORAGE_CONFIG_TOKEN=$(tr -d '-' < /proc/sys/kernel/random/uuid)
  if [[ ! "$PBM_STORAGE_CONFIG_TOKEN" =~ ^[A-Za-z0-9_-]{32,128}$ ]]; then
    echo "ERROR: Failed to generate PBM storage config token"
    exit 1
  fi
  PBM_STORAGE_CONFIG_FILE="$input_dir/$PBM_STORAGE_CONFIG_TOKEN"

  umask 077
  mkdir -p "$input_dir"
  chmod 0700 "$input_dir"
  if ! (set -o noclobber; write_pbm_storage_config_file "$PBM_STORAGE_CONFIG_FILE"); then
    echo "ERROR: Failed to create PVC-backed PBM storage config"
    exit 1
  fi
  chmod 0600 "$PBM_STORAGE_CONFIG_FILE"
  export PBM_STORAGE_CONFIG_FILE PBM_STORAGE_CONFIG_TOKEN
}

function prepare_restore_storage_config() {
  prepare_pbm_operation_storage_config
  RESTORE_STORAGE_CONFIG_FILE="$PBM_STORAGE_CONFIG_FILE"
  RESTORE_STORAGE_CONFIG_TOKEN="$PBM_STORAGE_CONFIG_TOKEN"
  RESTORE_REQUEST_ACCEPTED=false
  RESTORE_COMPLETED=false
  export RESTORE_STORAGE_CONFIG_FILE RESTORE_STORAGE_CONFIG_TOKEN RESTORE_REQUEST_ACCEPTED RESTORE_COMPLETED
}

function require_poll_attempt_budget() {
  local name=$1
  local value=$2
  if [[ ! "$value" =~ ^[1-9][0-9]*$ ]] || [ "${#value}" -gt 7 ]; then
    echo "ERROR: $name must be an integer in range 1..9999999, got '$value'"
    return 1
  fi
}

function wait_for_syncer_backup_completion() {
  local backup_name=$1
  local max_attempts=${SYNCER_PBM_WAIT_MAX_ATTEMPTS:-720}
  local retry_interval=${SYNCER_PBM_WAIT_INTERVAL_SECONDS:-5}
  local attempt=0
  require_poll_attempt_budget SYNCER_PBM_WAIT_MAX_ATTEMPTS "$max_attempts" || return 1
  describe_result=""
  while true; do
    if ! describe_result=$(syncerctl_cmd backup status --option "op_id=$backup_name" 2>&1); then
      echo "ERROR: Failed to read backup $backup_name status: $describe_result"
      return 1
    fi
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
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "ERROR: Backup $backup_name did not complete after $max_attempts attempts"
      return 1
    fi
    sleep "$retry_interval"
  done
}

function save_syncer_backup_info() {
  local response=$1
  local available
  available=$(echo "$response" | jq -r '.backup_info.available // false')
  if [ "$available" != "true" ]; then
    echo "INFO: Syncer reports no backup range available."
    return 1
  fi
  local total_size start_time end_time extras
  total_size=$(echo "$response" | jq -r '.backup_info.total_size // 0')
  start_time=$(echo "$response" | jq -r '.backup_info.start_time // empty')
  end_time=$(echo "$response" | jq -r '.backup_info.end_time // empty')
  extras=$(echo "$response" | jq -c '.backup_info.extras // {}')
  DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "$extras"
}

function wait_for_syncer_restore_completion() {
  local request_id=$1
  local max_attempts=${SYNCER_RESTORE_WAIT_MAX_ATTEMPTS:-7200}
  local retry_interval=${SYNCER_RESTORE_WAIT_INTERVAL_SECONDS:-1}
  local attempt=0
  local last_phase=""
  if [ -z "$request_id" ]; then
    echo "ERROR: Syncer restore start did not return request_id."
    exit 1
  fi
  require_poll_attempt_budget SYNCER_RESTORE_WAIT_MAX_ATTEMPTS "$max_attempts" || return 1
  while true; do
    local restore_status
    set +e
    restore_status=$(syncerctl_cmd restore status --option "request_id=$request_id" 2>&1)
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
    attempt=$((attempt + 1))
    if [ "$attempt" -ge "$max_attempts" ]; then
      echo "ERROR: Restore request $request_id did not complete after $max_attempts attempts"
      return 1
    fi
    sleep "$retry_interval"
  done
}

function run_pbm_full_backup() {
  set_backup_config_env
  prepare_pbm_operation_storage_config

  echo "INFO: Starting $PBM_BACKUP_TYPE backup for MongoDB through syncer..."
  backup_result=$(syncerctl_cmd backup start --option "type=$PBM_BACKUP_TYPE" --option "compression=$PBM_COMPRESSION" --option "storage_config_token=$PBM_STORAGE_CONFIG_TOKEN")
  rm -f "$PBM_STORAGE_CONFIG_FILE"
  PBM_STORAGE_CONFIG_FILE=""
  PBM_STORAGE_CONFIG_TOKEN=""
  backup_name=$(echo "$backup_result" | jq -r '.op_id // empty')
  if [ -z "$backup_name" ] || [ "$backup_name" = "null" ]; then
    echo "ERROR: syncer backup start did not return op_id: $backup_result"
    exit 1
  fi
  echo "INFO: Backup name: $backup_name"

  wait_for_syncer_backup_completion "$backup_name"

  echo "INFO: Backup status result:"
  echo "$(echo "$describe_result" | jq)"
  save_syncer_backup_info "$describe_result"
}

function run_pbm_full_restore() {
  prepare_restore_storage_config

  extras=$(cat /dp_downward/status_extras)
  backup_name=$(echo "$extras" | jq -r '.[0].backup_name // empty')
  backup_type=$(echo "$extras" | jq -r '.[0].backup_type // empty')

  if [ -z "$backup_type" ] || [ -z "$backup_name" ]; then
    echo "ERROR: Backup type or backup name is empty, skip restore."
    exit 1
  fi

  echo "INFO: Starting syncer physical restore..."
  if ! restore_result=$(syncerctl_cmd restore start --option "backup_name=$backup_name" --option type=physical --option "storage_config_token=$RESTORE_STORAGE_CONFIG_TOKEN" 2>&1); then
    echo "ERROR: Syncer restore start failed: $restore_result"
    exit 1
  fi
  RESTORE_REQUEST_ACCEPTED=true
  echo "INFO: Syncer restore start result: $restore_result"
  request_id=$(echo "$restore_result" | jq -r '.request_id // empty')

  wait_for_syncer_restore_completion "$request_id"
  RESTORE_COMPLETED=true
  echo "INFO: Restore completed."
}

function ensure_pbm_pitr_enabled() {
  local current_pitr_conf
  current_pitr_conf=$(syncerctl_cmd pitr status)
  local current_pitr_enabled
  local current_oplog_span_min
  local current_pitr_compression
  local current_purge_interval_seconds
  current_pitr_enabled=$(echo "$current_pitr_conf" | jq -r '.enabled // false')
  current_oplog_span_min=$(echo "$current_pitr_conf" | jq -r '.oplog_span_min // empty')
  current_pitr_compression=$(echo "$current_pitr_conf" | jq -r '.compression // empty')
  current_purge_interval_seconds=$(echo "$current_pitr_conf" | jq -r '.purge_interval_seconds // empty')

  if [ -n "${PBM_STORAGE_CONFIG_TOKEN:-}" ] || [ "$current_pitr_enabled" != "true" ] || [ "$current_oplog_span_min" != "$PBM_OPLOG_SPAN_MIN_MINUTES" ] || [ "$current_pitr_compression" != "$PBM_COMPRESSION" ] || [ "$current_purge_interval_seconds" != "$PBM_PURGE_INTERVAL_SECONDS" ]; then
    echo "INFO: Applying desired PITR configuration through syncer..."
    local args=(pitr enable --option "oplog_span_min=$PBM_OPLOG_SPAN_MIN_MINUTES" --option "compression=$PBM_COMPRESSION" --option "purge_interval_seconds=$PBM_PURGE_INTERVAL_SECONDS")
    if [ -n "${PBM_STORAGE_CONFIG_TOKEN:-}" ]; then
      args+=(--option "storage_config_token=$PBM_STORAGE_CONFIG_TOKEN")
    fi
    syncerctl_cmd "${args[@]}"
    if [ -n "${PBM_STORAGE_CONFIG_FILE:-}" ]; then
      rm -f "$PBM_STORAGE_CONFIG_FILE"
      PBM_STORAGE_CONFIG_FILE=""
      PBM_STORAGE_CONFIG_TOKEN=""
    fi
    echo "INFO: PITR config updated."
  fi
}

function upload_pbm_continuous_backup_info() {
  local status_result
  status_result=$(syncerctl_cmd pitr chunks)
  echo "INFO: Continuous backup result:"
  echo "$(echo "$status_result" | jq)"
  if save_syncer_backup_info "$status_result"; then
    echo "INFO: Continuous backup info uploaded."
  fi
}

function run_pbm_pitr_backup() {
  set_backup_config_env

  # Apply storage once through the first PITR enable call. Re-applying storage in
  # the loop clears PBM PITR settings and restarts slicing before chunks mature.
  prepare_pbm_operation_storage_config

  while true; do
    ensure_pbm_pitr_enabled
    upload_pbm_continuous_backup_info
    sleep 30
  done
}

function run_pbm_pitr_restore() {
  prepare_restore_storage_config

  recovery_target_time=$(date -d "@${DP_RESTORE_TIMESTAMP}" +"%Y-%m-%dT%H:%M:%S")
  echo "INFO: Recovery target time: $recovery_target_time"

  echo "INFO: Starting syncer PITR restore..."
  if ! restore_result=$(syncerctl_cmd restore start --option "pitr_target=$recovery_target_time" --option type=physical --option "storage_config_token=$RESTORE_STORAGE_CONFIG_TOKEN" 2>&1); then
    echo "ERROR: Syncer restore start failed: $restore_result"
    exit 1
  fi
  RESTORE_REQUEST_ACCEPTED=true
  echo "INFO: Syncer restore start result: $restore_result"
  request_id=$(echo "$restore_result" | jq -r '.request_id // empty')

  wait_for_syncer_restore_completion "$request_id"
  RESTORE_COMPLETED=true
  echo "INFO: Restore completed."
}

function handle_pbm_backup_exit() {
  exit_code=$?
  set +e
  if [ -n "${PBM_STORAGE_CONFIG_FILE:-}" ]; then
    rm -f "$PBM_STORAGE_CONFIG_FILE"
  fi
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

function handle_restore_exit() {
  exit_code=$?
  set +e
  if [ -n "${RESTORE_STORAGE_CONFIG_FILE:-}" ] && { [ "${RESTORE_REQUEST_ACCEPTED:-false}" != "true" ] || [ "${RESTORE_COMPLETED:-false}" = "true" ]; }; then
    rm -f "$RESTORE_STORAGE_CONFIG_FILE"
  fi
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    exit 1
  fi
}
