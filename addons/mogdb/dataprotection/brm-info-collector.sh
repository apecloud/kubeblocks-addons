function get_current_time() {
  curr_time=$(gsql -U ${DP_DB_USER} -h ${DP_DB_HOST} -W ${DP_DB_PASSWORD} -d postgres -t -c "SELECT now() AT TIME ZONE 'UTC'")
  echo $curr_time
}

function stat_and_save_backup_info() {
    local start_time="$1"
    local stop_time="$2"

    if [ -z $stop_time ]; then
        stop_time=$(get_current_time)
    fi

    start_time=$(date -d "${start_time}" -u '+%Y-%m-%dT%H:%M:%SZ')
    stop_time=$(date -d "${stop_time}" -u '+%Y-%m-%dT%H:%M:%SZ')

    local analysis=$(brm_analysis_log)
    local backup_id=$(jq -r .backup_id <<< $analysis)

    local backup_info=$(brm_backup_info "$backup_id")
    local size_bytes=$(jq -r '.[0].backups[0]."data-bytes"' <<< ${backup_info})
    local human_size=$(human_format $size_bytes)

    echo "{\"totalSize\":\"$human_size\",\"timeRange\":{\"start\":\"${start_time}\",\"end\":\"${stop_time}\"}}" >"${DP_BACKUP_INFO_FILE}"
}

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
