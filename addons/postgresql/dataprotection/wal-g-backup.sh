set -e
export WALG_DATASAFED_CONFIG=""
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export PGPASSWORD=${DP_DB_PASSWORD}

trap handle_exit EXIT

# cleanup the expired wal logs, will be retained for one more day than full backup.
function cleanup_archived_wal_logs() {
  if [[ -z $DP_TTL_SECONDS ]]; then
     return
  fi
  export DATASAFED_BACKEND_BASE_PATH="/${KB_NAMESPACE}/${KB_CLUSTER_NAME}-${KB_CLUSTER_UID}/${KB_COMP_NAME}/archive"
  local currentUnix=$(date +%s)
  expiredUnix=$((${currentUnix}-${DP_TTL_SECONDS}-86400))
  files=$(datasafed list -f --recursive --older-than ${expiredUnix} /wal_005)
  for file in ${files[@]}
  do
      datasafed rm ${file}
      echo "INFO: cleanup expired wal log ${file}"
  done
}
cleanup_archived_wal_logs

# do full backup
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
START_TIME=`get_current_time`
PGHOST=${DP_DB_HOST} PGUSER=${DP_DB_USER} PGPORT=5432 wal-g backup-push ${DATA_DIR}

STOP_TIME=""
for file in $(datasafed list /basebackups_005/  -f); do
   if [[ $file == *"backup_stop_sentinel.json" ]]; then
     datasafed pull $file backup_stop_sentinel.json
     result_json=$(cat backup_stop_sentinel.json)
     STOP_TIME=$(echo $result_json | jq -r ".FinishTime")
     START_TIME=$(echo $result_json | jq -r ".StartTime")
   fi
done
# stat and save the backup information
stat_and_save_backup_info "$START_TIME" "$STOP_TIME"