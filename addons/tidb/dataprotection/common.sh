#!/bin/bash

set -eo pipefail

function getToolConfigValue() {
  local var=$1
  grep "$var" < "$TOOL_CONFIG" | awk '{print $NF}'
}

# shellcheck disable=SC2034
function setStorageVar() {
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

function ensurePDAddress() {
  if [[ -n "${PD_ADDRESS:-}" ]]; then
    export PD_ADDRESS
    return 0
  fi

  local firstPD="${PD_POD_FQDN_LIST%%,*}"
  if [[ -n "$firstPD" ]]; then
    if [[ "$firstPD" == *:* ]]; then
      PD_ADDRESS="$firstPD"
    else
      PD_ADDRESS="$firstPD:2379"
    fi
    export PD_ADDRESS
    echo "PD_ADDRESS is empty; derived PD_ADDRESS=$PD_ADDRESS from PD_POD_FQDN_LIST"
    return 0
  fi

  echo "PD_ADDRESS is required but empty; set PD_ADDRESS or PD_POD_FQDN_LIST" >&2
  return 1
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
