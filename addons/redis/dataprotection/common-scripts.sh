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

# Get file names without extensions based on the incoming file path
function DP_get_file_name_without_ext() {
  local fileName=$1
  local file_without_ext=${fileName%.*}
  echo $(basename ${file_without_ext})
}

# Save backup status info file for syncing progress.
# timeFormat: %Y-%m-%dT%H:%M:%SZ
# receive timestamp
function DP_save_backup_status_info() {
  local totalSize=$1
  local startTime=$(date -u -d @$2 +%Y-%m-%dT%H:%M:%SZ)
  local stopTime=$(date -u -d @$3 +%Y-%m-%dT%H:%M:%SZ)
  local timeZone=$4
  local extras=$5
  local timeZoneStr=""
  if [ ! -z ${timeZone} ]; then
    timeZoneStr=",\"timeZone\":\"${timeZone}\""
  fi
  if [ -z "${stopTime}" ]; then
    echo "{\"totalSize\":\"${totalSize}\"}" >${DP_BACKUP_INFO_FILE}
  elif [ -z "${startTime}" ]; then
    echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"end\":\"${stopTime}\"${timeZoneStr}}}" >${DP_BACKUP_INFO_FILE}
  else
    echo "{\"totalSize\":\"${totalSize}\",\"extras\":[${extras}],\"timeRange\":{\"start\":\"${startTime}\",\"end\":\"${stopTime}\"${timeZoneStr}}}" >${DP_BACKUP_INFO_FILE}
  fi
}

function DP_pull_directory() {
  local dir_path="$1"
  local local_path="$2"

  while IFS= read -r filename; do
      datasafed pull "$filename" "${local_path}/${filename#*/}"
  done < <(datasafed list -r -f "$dir_path")
}

# Clean up expired logfiles.
# Default interval is 60s
# Default rootPath is /
function DP_purge_expired_files() {
  local currentUnix="${1:?missing current unix}"
  local last_purge_time="${2:?missing last_purge_time}"
  local root_path=${3:-"/"}
  local interval_seconds=${4:-60}
  local diff_time=$((${currentUnix} - ${last_purge_time}))
  if [[ -z ${DP_TTL_SECONDS} || ${diff_time} -lt ${interval_seconds} ]]; then
    return
  fi
  expiredUnix=$((${currentUnix} - ${DP_TTL_SECONDS}))
  files=$(datasafed list -f --recursive --older-than ${expiredUnix} ${root_path})
  for file in ${files[@]}; do
    datasafed rm ${file}
    echo ${file}
  done
}