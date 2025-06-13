#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

function handle_pitr_exit() {
  exit_code=$?
  if [ $exit_code -ne 0 ]; then
    echo "failed with exit code $exit_code"
    touch "${DP_BACKUP_INFO_FILE}.exit"
    exit 1
  fi
}

trap handle_pitr_exit EXIT

# Wait for the restore process
# RESTOREFILE=$DATA_DIR/mongodb.restore
# while [ -f "$RESTOREFILE" ]; do
#     echo "INFO: Restore process is running, waiting..."
#     sleep 5
# done

export_pbm_env_vars

set_backup_config_env

echo "INFO: Checking if PBM config exists for backup path: $S3_PREFIX"
check_profile=$(pbm config --mongodb-uri "$PBM_MONGODB_URI" -o json | jq -r '.storage.s3.prefix')
echo "INFO: Current PBM config prefix: $check_profile"
if [ "$check_profile" = "$S3_PREFIX" ]; then
    echo "INFO: PBM config already exists."
else
cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin > /dev/null
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${S3_PREFIX}
    endpointUrl: ${S3_ENDPOINT}
    forcePathStyle: ${S3_FORCE_PATH_STYLE:-false}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
EOF
echo "INFO: PBM storage configuration completed."
fi

echo "INFO: Starting continuous backup for MongoDB..."
backup_result=$(pbm backup --type=continuous --mongodb-uri "$PBM_MONGODB_URI" --wait -o json)
backup_name=$(echo "$backup_result" | jq -r '.name')
extras=$(buildJsonString "" "backup_name" "$backup_name")

describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json)
backup_status=$(echo "$describe_result" | jq -r '.status')

if [ "$backup_status" != "done" ]; then
    echo "ERROR: Backup failed with status: $backup_status"
    exit 1
fi

echo "INFO: Backup description result:"
echo "$(echo $describe_result | jq)"
start_time=$(echo "$describe_result" | jq -r '.name')
end_time=$(echo "$describe_result" | jq -r '.last_write_time')
total_size=$(echo "$describe_result" | jq -r '.size')
DP_save_backup_status_info "$total_size" "$start_time" "$end_time" "" "{$extras}"
