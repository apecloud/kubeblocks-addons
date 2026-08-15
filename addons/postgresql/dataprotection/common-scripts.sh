#!/bin/bash
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

function DP_get_backup_total_size() {
    local statOutput
    local totalSize
    if ! statOutput=$(datasafed stat /); then
      DP_error_log "datasafed stat failed" >&2
      return 1
    fi
    totalSize=$(printf '%s\n' "${statOutput}" | awk '/TotalSize/ { print $2; exit }')
    if [[ ! ${totalSize} =~ ^[0-9]+$ ]]; then
      DP_error_log "datasafed stat returned an invalid TotalSize" >&2
      return 1
    fi
    printf '%s\n' "${totalSize}"
}

function DP_list_backup_files_by_mtime() {
    local listOutput
    local sortedFiles
    if ! listOutput=$(datasafed list -f --recursive / -o json); then
      DP_error_log "datasafed WAL listing failed" >&2
      return 1
    fi
    if ! sortedFiles=$(printf '%s\n' "${listOutput}" | jq -s -r '
      .[]
      | map(select(.path | test("/[0-9A-F]{24}(\\.partial)?\\.zst$")))
      | sort_by(.mtime)
      | .[]
      | .path
    '); then
      DP_error_log "datasafed WAL listing returned invalid JSON" >&2
      return 1
    fi
    printf '%s\n' "${sortedFiles}"
}

# Get file names without extensions based on the incoming file path
function DP_get_file_name_without_ext() {
    local fileName=$1
    local file_without_ext=${fileName%.*}
    echo $(basename ${file_without_ext})
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
    local backupInfo
    local backupInfoTmp="${DP_BACKUP_INFO_FILE}.tmp.$$"
    if [ ! -z ${timeZone} ]; then
       timeZoneStr=",\"timeZone\":\"${timeZone}\""
    fi
    if [ -z "${stopTime}" ];then
      printf -v backupInfo '{"totalSize":"%s"}' "${totalSize}"
    elif [ -z "${startTime}" ];then
      printf -v backupInfo '{"totalSize":"%s","extras":[%s],"timeRange":{"end":"%s"%s}}' \
        "${totalSize}" "${extras}" "${stopTime}" "${timeZoneStr}"
    else
      printf -v backupInfo '{"totalSize":"%s","extras":[%s],"timeRange":{"start":"%s","end":"%s"%s}}' \
        "${totalSize}" "${extras}" "${startTime}" "${stopTime}" "${timeZoneStr}"
    fi
    if ! printf '%s\n' "${backupInfo}" > "${backupInfoTmp}"; then
      rm -f "${backupInfoTmp}"
      return 1
    fi
    if ! mv -f "${backupInfoTmp}" "${DP_BACKUP_INFO_FILE}"; then
      rm -f "${backupInfoTmp}"
      return 1
    fi
}

# Clean up expired logfiles.
# Default interval is 60s
# Default rootPath is /
function DP_purge_expired_files() {
  local currentUnix="${1:?missing current unix}"
  local last_purge_time="${2:?missing last_purge_time}"
  local root_path=${3:-"/"}
  local interval_seconds=${4:-60}
  local diff_time=$((${currentUnix}-${last_purge_time}))
  if [[ -z ${DP_TTL_SECONDS} || ${diff_time} -lt ${interval_seconds} ]]; then
     return
  fi
  local expiredUnix=$((${currentUnix}-${DP_TTL_SECONDS}))
  local files
  if ! files=$(datasafed list -f --recursive --older-than ${expiredUnix} ${root_path}); then
      DP_error_log "failed to list expired WAL files" >&2
      return 1
  fi
  local purge_failed=false
  for file in ${files}
  do
      if datasafed rm ${file}; then
          echo ${file}
      else
          DP_error_log "failed to remove expired WAL: ${file}" >&2
          purge_failed=true
      fi
  done
  if [[ ${purge_failed} == "true" ]]; then
      return 1
  fi
}

# analyze the start time of the earliest file from the datasafed backend.
# Then record the file name into dp_oldest_file.info.
# If the oldest file is no changed, exit the process.
# This can save traffic consumption.
function DP_analyze_start_time_from_datasafed() {
    local oldest_file="${1:?missing oldest file}"
    local get_start_time_from_file="${2:?missing get_start_time_from_file function}"
    local datasafed_pull="${3:?missing datasafed_pull function}"
    local info_file="${KB_BACKUP_WORKDIR}/dp_oldest_file.info"
    mkdir -p ${KB_BACKUP_WORKDIR} && cd ${KB_BACKUP_WORKDIR}
    if [ -f ${info_file} ]; then
      last_oldest_file=$(cat ${info_file})
      last_oldest_file_name=$(DP_get_file_name_without_ext ${last_oldest_file})
      if [ "$last_oldest_file" == "${oldest_file}" ] && [ -f ${last_oldest_file_name} ]; then
        # oldest file no changed.
        ${get_start_time_from_file} $last_oldest_file_name
        return
      fi
         # remove last oldest file
      if [ -f ${last_oldest_file_name} ];then
          rm -rf ${last_oldest_file_name}
      fi
    fi
    # pull file
    if ! ${datasafed_pull} ${oldest_file}; then
      DP_error_log "failed to pull oldest WAL" >&2
      return 1
    fi
    # record last oldest file
    echo ${oldest_file} > ${info_file}
    oldest_file_name=$(DP_get_file_name_without_ext ${oldest_file})
    ${get_start_time_from_file} ${oldest_file_name}
}

# get the timeZone offset for location, such as Asia/Shanghai
function getTimeZoneOffset() {
   local timeZone=${1:?missing time zone}
   if [[ $timeZone == "+"* ]] || [[ $timeZone == "-"* ]] ; then
      echo ${timeZone}
      return
   fi
   local currTime=$(TZ=UTC date)
   local utcHour=$(TZ=UTC date -d "${currTime}" +"%H")
   local zoneHour=$(TZ=${timeZone} date -d "${currTime}" +"%H")
   local offset=$((${zoneHour}-${utcHour}))
   if [ $offset -eq 0 ]; then
      return
   fi
   symbol="+"
   if [ $offset -lt 0 ]; then
     symbol="-" && offset=${offset:1}
   fi
   if [ $offset -lt 10 ];then
      offset="0${offset}"
   fi
   echo "${symbol}${offset}:00"
}
