#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

export_pbm_env_vars_for_rs

set_backup_config_env

export_logs_start_time_env

trap handle_restore_exit EXIT

# wait_for_restore_op_id polls the restore-coord ConfigMap that syncer creates
# during a physical restore. syncer's initiatePhysical HTTP handler returns an
# empty op_id because the actual PBM restore is started asynchronously by the
# dataprotection loop, so we read the op_id from the coord CM annotation.
function wait_for_restore_op_id() {
  local coord_cm="${CLUSTER_NAME}-restore-coord"
  local retry_count=0
  local max_retries=60
  while [ $retry_count -lt $max_retries ]; do
    local op_id
    op_id=$(kubectl get configmap -n "$CLUSTER_NAMESPACE" "$coord_cm" -o jsonpath='{.metadata.annotations.restore\.syncer/op-id}' 2>/dev/null)
    if [ -n "$op_id" ]; then
      echo "$op_id"
      return 0
    fi
    retry_count=$((retry_count+1))
    echo "INFO: Waiting for restore-coord op-id... ($retry_count/$max_retries)" >&2
    sleep 5
  done
  # Empty stdout tells the caller no op-id was found.
  return 0
}

# The ActionSet job renders PBM storage config from datasafed, and restore
# targets must force PBM to resync metadata before syncer starts the restore.
# The mongodb container startup path already applied the prepared config, so
# these calls are idempotent; the extra wait prevents a force-resync lock from
# colliding with the restore command.
wait_for_other_operations
sync_pbm_storage_config
sync_pbm_config_from_storage
wait_for_other_operations

extras=$(cat /dp_downward/status_extras)
backup_name=$(echo "$extras" | jq -r '.[0].backup_name')
backup_type=$(echo "$extras" | jq -r '.[0].backup_type')

if [ -z "$backup_type" ] || [ -z "$backup_name" ]; then
    echo "ERROR: Backup type or backup name is empty, skip restore."
    exit 1
fi

# Get backup info for replset name mapping via syncerctl. PBM may need a few
# seconds after resync before the backup metadata is visible, so poll briefly.
echo "INFO: Getting backup info for replset mapping..."
rs_name=""
retry_count=0
max_retries=60
while [ $retry_count -lt $max_retries ]; do
  describe_result=$(syncerctl_exec backup status --op-id "$backup_name")
  if [ -n "$describe_result" ]; then
    found=$(echo "$describe_result" | jq -r '.found // empty')
    if [ "$found" = "true" ]; then
      rs_name=$(echo "$describe_result" | jq -r '.replsets[0].name // empty')
      if [ -n "$rs_name" ]; then
        break
      fi
    fi
  fi
  retry_count=$((retry_count+1))
  echo "INFO: Backup metadata not ready yet, retrying... ($retry_count/$max_retries)"
  sleep 5
done

if [ -z "$rs_name" ]; then
  echo "ERROR: Failed to get backup replset name after $max_retries retries"
  exit 1
fi

mappings="$MONGODB_REPLICA_SET_NAME=$rs_name"
echo "INFO: Replica set mappings: $mappings"

process_restore_start_signal

# Trigger restore via syncerctl instead of direct pbm restore. For physical
# restores syncer returns an empty op_id immediately; the actual op_id is set
# on the restore-coord ConfigMap once the dataprotection loop starts PBM.
echo "INFO: Starting restore via syncerctl..."
set +e
restore_result=$(syncerctl_exec restore start --backup-name "$backup_name" --replset-remapping "$mappings" 2>&1)
restore_start_exit=$?
set -e
if [ $restore_start_exit -ne 0 ]; then
  echo "INFO: syncerctl restore start returned $restore_start_exit: $restore_result"
fi

echo "INFO: Resolving restore operation id..."
restore_name=$(echo "$restore_result" | jq -r '.op_id // empty' || true)
if [ -z "$restore_name" ]; then
  restore_name=$(wait_for_restore_op_id)
fi

if [ -z "$restore_name" ]; then
  echo "ERROR: Failed to get restore operation id"
  exit 1
fi

echo "INFO: Restore operation id: $restore_name"

# Poll restore status via syncerctl
echo "INFO: Waiting for restore completion..."
retry_interval=5
attempt=0
max_retries=360
set +e
while true; do
  restore_status_result=$(syncerctl_exec restore status --op-id "$restore_name")
  if [ $? -eq 0 ] && [ -n "$restore_status_result" ]; then
    found=$(echo "$restore_status_result" | jq -r '.found // empty')
    if [ "$found" = "false" ]; then
      echo "INFO: Restore status not available yet, retrying..."
    else
      status=$(echo "$restore_status_result" | jq -r '.status // empty')
      echo "INFO: Restore $restore_name status: $status"
      if [ "$status" = "done" ]; then
        break
      elif [ "$status" = "error" ]; then
        echo "ERROR: Restore failed"
        set -e
        exit 1
      fi
    fi
  else
    echo "INFO: Failed to get restore status, retrying..."
    attempt=$((attempt+1))
  fi
  sleep $retry_interval
  if [ $attempt -gt $max_retries ]; then
    echo "ERROR: Restore status polling exceeded $max_retries retries"
    set -e
    exit 1
  fi
done
set -e

process_restore_end_signal

echo "INFO: Restore completed."
