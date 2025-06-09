# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
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

  export S3_ACCESS_KEY="${access_key_id}"
  export S3_SECRET_KEY="${secret_access_key}"
  export S3_REGION="${region}"
  export S3_ENDPOINT="${endpoint}"
  export S3_BUCKET="${bucket}"

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
