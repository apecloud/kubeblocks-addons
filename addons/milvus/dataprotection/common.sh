#!/bin/bash

set -eo pipefail

function getToolConfigValue() {
  local var=$1
  grep "$var" < "$TOOL_CONFIG" | awk '{print $NF}'
}

# shellcheck disable=SC2034
function setStorageConfig() {
  TOOL_CONFIG=/etc/datasafed/datasafed.conf

  ACCESS_KEY_ID=$(getToolConfigValue access_key_id)
  SECRET_ACCESS_KEY=$(getToolConfigValue secret_access_key)
  ENDPOINT=$(getToolConfigValue endpoint)
  BUCKET=$(getToolConfigValue "root =")
  PROVIDER=$(getToolConfigValue provider)

  if [[ "$PROVIDER" == "Alibaba" ]]; then
    ENDPOINT="https://${ENDPOINT}"
  fi

  export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
  export DATASAFED_BACKEND_BASE_PATH=${DP_BACKUP_BASE_PATH}

  # only underscores are allowed in backup name
  BACKUP_NAME=${DP_BACKUP_NAME//-/_}

  BACKUP_CONFIG=configs/backup.yaml
  MILVUS_CONFIG=/milvus/configs/user.yaml

  if [[ -z $DP_DB_PORT ]]; then
    DP_DB_PORT=19530
  fi

  # connection config
  yq -i ".milvus.address = \"$DP_DB_HOST\"" "$BACKUP_CONFIG"
  yq -i ".milvus.port = $DP_DB_PORT" "$BACKUP_CONFIG"
  yq -i ".milvus.user = \"\"" "$BACKUP_CONFIG"
  yq -i ".milvus.password = \"\"" "$BACKUP_CONFIG"
  yq -i ".backup.gcPause.address = \"http://$DP_DB_HOST:9091\"" "$BACKUP_CONFIG"

  # milvus storage config
  yq -i ".minio.address = \"$MINIO_HOST\"" "$BACKUP_CONFIG"
  yq -i ".minio.port = \"$MINIO_PORT\"" "$BACKUP_CONFIG"
  yq -i ".minio.accessKeyID = \"$MINIO_ACCESS_KEY\"" "$BACKUP_CONFIG"
  yq -i ".minio.secretAccessKey = \"$MINIO_SECRET_KEY\"" "$BACKUP_CONFIG"

  yq -i ".minio.bucketName = \"$MINIO_BUCKET\"" "$BACKUP_CONFIG"
  if [[ $MINIO_PORT == "443" ]]; then
    yq -i ".minio.useSSL = true" "$BACKUP_CONFIG"
  fi
  yq -i ".minio.rootPath = \"$MINIO_ROOT_PATH\"" "$BACKUP_CONFIG"
  # TODO: is this right?
  yq -i ".minio.storageType = (load(\"$MILVUS_CONFIG\") | .minio.cloudProvider)" "$BACKUP_CONFIG"

  # backup storage config
  without_scheme=${ENDPOINT#http://}
  IFS=":" read -r -a parts <<< "$without_scheme"
  yq -i ".minio.backupAddress = \"${parts[0]}\"" "$BACKUP_CONFIG"
  # FIXME: will backupPort be empty?
  yq -i ".minio.backupPort = \"${parts[1]}\"" "$BACKUP_CONFIG"
  yq -i ".minio.backupAccessKeyID = \"$ACCESS_KEY_ID\"" "$BACKUP_CONFIG"
  yq -i ".minio.backupSecretAccessKey = \"$SECRET_ACCESS_KEY\"" "$BACKUP_CONFIG"
  yq -i ".minio.backupBucketName = \"$BUCKET\"" "$BACKUP_CONFIG"
  # eliminate the leading slash, or go-minio will return an empty list when listing
  BACKUP_ROOT_PATH=${DP_BACKUP_BASE_PATH#/}
  yq -i ".minio.backupRootPath = \"$BACKUP_ROOT_PATH\"" "$BACKUP_CONFIG"
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
