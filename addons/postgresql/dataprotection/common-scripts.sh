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
  expiredUnix=$((${currentUnix}-${DP_TTL_SECONDS}))
  files=$(datasafed list -f --recursive --older-than ${expiredUnix} ${root_path} )
  for file in ${files[@]}
  do
      datasafed rm ${file}
      echo ${file}
  done
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
      if [ "$last_oldest_file" == "${oldest_file}" ]; then
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
    ${datasafed_pull} ${oldest_file}
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

