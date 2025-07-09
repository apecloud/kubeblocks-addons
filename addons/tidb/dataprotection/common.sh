#!/bin/bash

set -exo pipefail

function getToolConfigValue() {
  local var=$1
  grep "$var" < "$TOOL_CONFIG" | awk '{print $NF}'
}

# shellcheck disable=SC2034
function setStorageVar() {
  cat /etc/datasafed/datasafed.conf
  TOOL_CONFIG=/etc/datasafed/datasafed.conf

  ACCESS_KEY_ID=$(getToolConfigValue access_key_id)
  SECRET_ACCESS_KEY=$(getToolConfigValue secret_access_key)
  ENDPOINT=$(getToolConfigValue endpoint)
  BUCKET=$(getToolConfigValue "root =")
  PROVIDER=$(getToolConfigValue provider)

  BR_EXTRA_ARGS=""
  if [[ "$PROVIDER" == "Alibaba" ]]; then
    ENDPOINT="https://${ENDPOINT}"
    BR_EXTRA_ARGS="--s3.provider alibaba"
  fi

  export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
  export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}
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
  if [ -n "${timeZone}" ]; then
    timeZoneStr=$(printf ',"timeZone":"%s"' "${timeZone}")
  fi
  if [ -z "${stopTime}" ]; then
    printf '{"totalSize":"%s"}' "${totalSize}" > "${DP_BACKUP_INFO_FILE}"
  elif [ -z "${startTime}" ]; then
    printf '{"totalSize":"%s","extras":[%s],"timeRange":{"end":"%s"%s}}' "${totalSize}" "${extras}" "${stopTime}" "${timeZoneStr}" > "${DP_BACKUP_INFO_FILE}"
  else
    printf '{"totalSize":"%s","extras":[%s],"timeRange":{"start":"%s","end":"%s"%s}}' "${totalSize}" "${extras}" "${startTime}" "${stopTime}" "${timeZoneStr}" > "${DP_BACKUP_INFO_FILE}"
  fi
}
