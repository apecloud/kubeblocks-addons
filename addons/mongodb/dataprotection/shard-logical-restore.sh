#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_exit EXIT

export_pbm_env_vars

set_backup_config_env

cat <<EOF | pbm config --mongodb-uri "$PBM_MONGODB_URI" --file /dev/stdin
storage:
  type: s3
  s3:
    region: ${S3_REGION}
    bucket: ${S3_BUCKET}
    prefix: ${DP_BACKUP_BASE_PATH#/}
    endpointUrl: ${S3_ENDPOINT}
    forcePathStyle: ${S3_FORCE_PATH_STYLE:-false}
    credentials:
      access-key-id: ${S3_ACCESS_KEY}
      secret-access-key: ${S3_SECRET_KEY}
EOF
echo "INFO: PBM storage configuration completed."

pbm config --force-resync --mongodb-uri "$PBM_MONGODB_URI"
extras=$(cat /dp_downward/status_extras)
backup_name=$(echo "$extras" | jq -r '.[0].backup_name')

MAX_RETRIES=360
RETRY_INTERVAL=2
attempt=1
describe_result=""
set +e
while [ $attempt -le $MAX_RETRIES ]; do
    describe_result=$(pbm describe-backup --mongodb-uri "$PBM_MONGODB_URI" "$backup_name" -o json 2>&1)
    if [ $? -eq 0 ] && [ -n "$describe_result" ]; then
        break
    elif echo "$describe_result" | grep -q "not found"; then
        echo "INFO: Attempt $attempt: Failed to get backup metadata, retrying in ${RETRY_INTERVAL}s..."
        sleep $RETRY_INTERVAL
        ((attempt++))
        continue
    else
        echo "ERROR: Failed to get backup metadata: $describe_result"
    fi
done
set -e

if [ -z "$describe_result" ]; then
    echo "ERROR: Failed to get backup metadata after $MAX_RETRIES attempts"
    exit 1
fi

configsvr_name=$(echo "$describe_result" | jq -r '.replsets[] | select(.configsvr == true) | .name')
echo "INFO: Config server replica set name: $configsvr_name"
shardsvr_names=$(echo "$describe_result" | jq -r '[.replsets[] | select(.configsvr != true) | .name] | join(",")')
echo "INFO: Shard replica set names: $shardsvr_names"
mappings=""
IFS="," read -r -a shardsvr_array <<< "$shardsvr_names"
IFS="." read -r -a new_shardsvr_array <<< "$MONGODB_SHARD_REPLICA_SET_NAME_LIST"
for i in "${!shardsvr_array[@]}"; do
    # Get the part before "@" in new_shardsvr_array
    shard_name="$KB_CLUSTER_NAME-${new_shardsvr_array[i]%%@*}"
    echo "INFO: Mapping shard ${shardsvr_array[i]} to $shard_name"
    if [ $i -eq 0 ]; then
        mappings="${shard_name}=${shardsvr_array[i]}"
    else
        mappings="$mappings,${shard_name}=${shardsvr_array[i]}"
    fi
done
# If the config server name is not empty, add it to the mappings
echo "INFO: Mapping config server $configsvr_name to $CFG_SERVER_REPLICA_SET_NAME"
mappings="$mappings,$CFG_SERVER_REPLICA_SET_NAME=$configsvr_name"
echo "INFO: Shard mappings: $mappings"

# check if restore is running in case of fallback
if pbm status --mongodb-uri "$PBM_MONGODB_URI" | grep -q "restore"; then
    echo "ERROR: Restore is already running, cannot start a new restore."
    exit 1
fi
pbm restore $backup_name --mongodb-uri "$PBM_MONGODB_URI" --replset-remapping "$mappings" --wait
