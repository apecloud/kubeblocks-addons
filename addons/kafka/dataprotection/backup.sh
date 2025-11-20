#!/bin/bash

set -eo pipefail

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

readarray -t topics < <(kafkactl get topics -o compact)
for topic in "${topics[@]}"; do
  kafkactl consume new "${topic}" --from-beginning --print-keys --print-timestamps --exit --print-headers -o json-raw > "${topic}.json"
done
# TODO: store topics
