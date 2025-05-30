#!/bin/bash

function save_backup_status() {
    # shellcheck disable=SC2086
    res=$(/br log status --task-name=pitr --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $EXTRA_ARGS)
    start_time_str=$(echo "$res" | awk -F': ' '/^\s*start:/ {print $2}')
    checkpoint_time_str=$(echo "$res" | awk -F': ' '/^checkpoint\[global\]:/ {print $2}' | cut -d';' -f1)
    start_time=$(date -d "$start_time_str" -u '+%Y-%m-%dT%H:%M:%SZ')
    checkpoint_time=$(date -d "$checkpoint_time_str" -u '+%Y-%m-%dT%H:%M:%SZ')

    # use datasafed to get backup size
    total_size=$(datasafed stat / | grep TotalSize | awk '{print $2}')
    echo "start_time: $start_time, checkpoint_time: $checkpoint_time, total_size: $total_size"
    DP_save_backup_status_info "$total_size" "$start_time" "$checkpoint_time" "" ""
}

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
  exit_code=$?
  save_backup_status
  # shellcheck disable=SC2086
  /br log stop --task-name=pitr --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $EXTRA_ARGS
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    exit $exit_code
  fi
}

trap handle_exit EXIT

setStorageVar

echo "start log backup"
# shellcheck disable=SC2086
/br log start --task-name=pitr --pd "$PD_ADDRESS" --storage "s3://$BUCKET$DP_BACKUP_BASE_PATH?access-key=$ACCESS_KEY_ID&secret-access-key=$SECRET_ACCESS_KEY" --s3.endpoint "$ENDPOINT" $BR_EXTRA_ARGS

set +x
while true; do
  save_backup_status
  # todo: prune outdated log
  sleep 20
done
