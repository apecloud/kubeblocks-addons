#!/bin/bash
set -ex
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
export HADOOP_LOG_DIR=/hadoop/logs
export HADOOP_CONF_DIR=/hadoop/conf

. /opt/scripts/libs/libos.sh

backup_metadata(){
  cd /hadoop/dfs/journal
  tar -cvf - ./ | datasafed push -z zstd-fastest - "journal.tar.zst"
  TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
  echo "{\"totalSize\":\"$TOTAL_SIZE\"}" > "${DP_BACKUP_INFO_FILE}"
}

backup_metadata
