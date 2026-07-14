#!/bin/bash

provider=
access_key_id=
secret_access_key=
region=
endpoint=
bucket=

json_get() {
  local key="$1"
  echo "$2" | grep -o "\"${key}\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 | sed 's/.*:[[:space:]]*"\(.*\)"/\1/'
}

json_array_len() {
  echo "$1" | grep -o '{' | wc -l | tr -d ' '
}

json_array_get() {
  local idx="$1" key="$2"
  local elem
  elem=$(echo "$3" | grep -o '{[^}]*}' | sed -n "$((idx+1))p")
  json_get "$key" "$elem"
}

OB_MYSQL_BIN=""
detect_mysql_bin() {
  if [ -n "$OB_MYSQL_BIN" ]; then
    return
  fi
  for candidate in mysql /usr/bin/mysql obclient /u01/obclient/bin/obclient; do
    if command -v "$candidate" >/dev/null 2>&1; then
      OB_MYSQL_BIN="$candidate"
      return
    fi
  done
  echo "ERROR: no mysql-compatible client found (tried mysql, obclient)"
  exit 1
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

function getToolConfigValue() {
    local line=${1}
    value=${line#*=}
    echo $(eval echo $value)
}

function analysisToolConfig() {
  toolConfig=/etc/datasafed/datasafed.conf
  if [ ! -f ${toolConfig} ];then
      DP_error_log "backupRepo should use Tool accessMode"
      exit 1
  fi
  IFS=$'\n'
  for line in `cat ${toolConfig}`; do
    # remove space
    line=$(eval echo $line)
    IFS=$OlD_IFS
    if [[ $line == "provider"* ]];then
       provider=$(getToolConfigValue "$line")
    elif [[ $line == "access_key_id"* ]];then
       access_key_id=$(getToolConfigValue "$line")
    elif [[ $line == "secret_access_key"* ]];then
       secret_access_key=$(getToolConfigValue "$line")
    elif [[ $line == "region"* ]];then
       region=$(getToolConfigValue "$line")
    elif [[ $line == "endpoint"* ]];then
       endpoint=$(getToolConfigValue "$line")
    elif [[ $line == "root"* ]];then
       bucket=$(getToolConfigValue "$line")
    fi
  done
  if [[ ${SUPPORT_S3} != "true" ]] && [[ "${provider}" != "Alibaba" ]] && [[ "${provider}" != "TencentCOS" ]];then
     echo "ERROR: unsupported storage provider \"${provider}\""
     exit 1
  fi
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

# get the storage host by storage provider and endpoint
function getStorageHost() {
    if [[ ! -z ${endpoint} ]]; then
       replaceK8sSVC "${endpoint}"
       return
    fi
    if [[ ${provider} == "Alibaba" ]];then
       echo "oss-${DP_STORAGE_REGION}.aliyuncs.com"
    elif [[ ${provider} == "TencentCOS" ]];then
       echo "cos.${DP_STORAGE_REGION}.myqcloud.com"
    elif [[ ${provider} == "AWS" ]]; then
       echo "s3.${DP_STORAGE_REGION}.amazonaws.com"
    fi
}

function replaceK8sSVC() {
    local localEndpoint="${1}"
    local scheme=""
    local address="${localEndpoint}"
    case "${address}" in
      [hH][tT][tT][pP]://*|[hH][tT][tT][pP][sS]://*)
        scheme="${address%%://*}://"
        address="${address#*://}"
        ;;
    esac

    local host="${address%%:*}"
    local port=""
    if [[ ${address} == *":"* ]]; then
       port="${address#*:}"
    fi
    if [[ ${host} == *.svc || ${host} == *.svc.* ]]; then
       local hostIP resolverOutput
       if resolverOutput=$(getent hosts "${host}" 2>/dev/null); then
         hostIP=$(awk '
         $1 ~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ {
           split($1, octets, ".")
           canonical = 1
           for (i = 1; i <= 4; i++) {
             if (octets[i] !~ /^(0|[1-9][0-9]*)$/ || octets[i] > 255) {
               canonical = 0
             }
           }
           if (canonical) {
             print $1
             exit
           }
         }
         ' <<< "${resolverOutput}")
         if [[ -n ${hostIP} ]]; then
            if [[ -n ${port} ]]; then
               echo "${scheme}${hostIP}:${port}"
            else
               echo "${scheme}${hostIP}"
            fi
            return
         fi
       fi
    fi
    echo "${localEndpoint}"
}

function get_pod_ordinal() {
  local ordinal=-1
  for pod_name in $(echo $OB_POD_LIST | tr "," "\n"); do
    ordinal=$(($ordinal + 1))
    if [ "${pod_name}" == "$1" ]; then
       echo $ordinal
       break
    fi
  done
}

function getArchiveDestPath() {
    # TODO: support nfs
    path="$(dirname ${DP_BACKUP_BASE_PATH})/archive"
    pod_ordinal=$(get_pod_ordinal ${DP_TARGET_POD_NAME})
    if [ ${pod_ordinal} -ne 0 ]; then
       path="${path}/${DP_TARGET_POD_NAME}"
    fi
    echo $path
}

# get the backup dest url
function getDestURL() {
  destType=${1:?missing destType}
  tenantName=${2:?missing tenantName}
  tenantId=${3}
  archivePath=${4}
  host=$(getStorageHost)
  if [[ -z $host ]];then
     echo "ERROR: can not get the endpoint for \"${provider}\""
     exit 1
  fi
  # TODO: support nfs and cos
  destPath="${DP_BACKUP_BASE_PATH}"
  if [[ $destType == "archive" ]]; then
     destPath=$(getArchiveDestPath)
  elif [[ $destType == "restoreFromArchive" ]]; then
     destPath=${archivePath}
  fi
  destPrefix="s3"
  prefixHost=${host}
  case "${prefixHost}" in
    [hH][tT][tT][pP]://*|[hH][tT][tT][pP][sS]://*)
      prefixHost="${prefixHost#*://}"
      ;;
  esac
  if [[ ${prefixHost} == "cos"* ]]; then
     destPrefix="cos"
  elif [[ ${prefixHost} == "oss"* ]]; then
     destPrefix="oss"
  fi
  destUrl="${destPrefix}://${bucket}${destPath}/${tenantName}/${tenantId}?host=${host}&access_id=${access_key_id}&access_key=${secret_access_key}"
  if [[ ${destPrefix} == "s3" && ${provider} == "AWS" ]]; then
     storageRegion=${region:-${DP_STORAGE_REGION:-}}
     if [[ -z ${storageRegion} ]]; then
        echo "ERROR: s3_region is required for AWS S3 storage"
        exit 1
     fi
     destUrl="${destUrl}&s3_region=${storageRegion}"
  fi
  echo "${destUrl}"
}
