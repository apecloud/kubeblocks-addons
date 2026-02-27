#!/bin/bash
set -o pipefail

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
trap handle_exit EXIT

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
connect_url="redis-cli $REDIS_CLI_TLS_CMD -h ${DP_DB_HOST} -p ${DP_DB_PORT} -a ${DP_DB_PASSWORD}"
if [ -z ${DP_DB_PASSWORD} ]; then
  connect_url="redis-cli $REDIS_CLI_TLS_CMD -h ${DP_DB_HOST} -p ${DP_DB_PORT}"
fi
last_save=$(${connect_url} LASTSAVE)
echo "INFO: start BGSAVE"
${connect_url} BGSAVE
echo "INFO: wait for saving rdb successfully"
while true; do
  persistence_info=$(${connect_url} INFO persistence)
  bgsave_in_progress=$(echo "$persistence_info" | grep rdb_bgsave_in_progress | tr -d '\r' | cut -d: -f2)
  if [ "$bgsave_in_progress" = "0" ]; then
    bgsave_status=$(echo "$persistence_info" | grep rdb_last_bgsave_status | tr -d '\r' | cut -d: -f2)
    if [ "$bgsave_status" = "err" ]; then
      echo "ERROR: BGSAVE failed on target pod"
      exit 1
    fi
    echo "INFO: BGSAVE completed (no changes since last save)"
    break
  fi
  sleep 3
done
echo "INFO: start to save data file..."
cd ${DATA_DIR}
if [ "${MODE}" == "cluster" ]; then
  # only save rdb file for redis cluster.
  datasafed push -z zstd-fastest ./dump.rdb "${DP_BACKUP_NAME}.rdb.zst"
  datasafed push ./nodes.conf "nodes.conf"
  datasafed push ./users.acl "users.acl"
  export DATASAFED_BACKEND_BASE_PATH="$(dirname $DP_BACKUP_BASE_PATH)"
else
  # NOTE: if files changed during taring, the exit code will be 1 when it ends.
  # and will archive the aof file together.
  tar -cvf - ./ | datasafed push -z zstd-fastest - "${DP_BACKUP_NAME}.tar.zst"
fi
echo "INFO: save data file successfully"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}" && sync