#!/bin/bash
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:$MOUNT_DIR/tmp/bin"

# shellcheck source=common-scripts.sh
if ! command -v syncerctl_restore_start >/dev/null 2>&1; then
  . "$(dirname "$0")/common-scripts.sh"
fi

# wait_for_restore_op_id polls the restore-coord ConfigMap for the op-id that
# the syncer leader writes after it actually starts PBM restore.
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

extras=$(cat /dp_downward/status_extras)
backup_name=$(echo "$extras" | jq -r '.[0].backup_name')
backup_type=$(echo "$extras" | jq -r '.[0].backup_type')

if [ -z "$backup_type" ] || [ -z "$backup_name" ]; then
    echo "ERROR: Backup type or backup name is empty, skip restore."
    exit 1
fi

# Get backup info for replset name mapping via syncerctl. PBM may need a few
# seconds after the config-server primary applies the storage config before the
# backup metadata is visible, so poll briefly.
echo "INFO: Getting backup info for replset mapping..."
rs_name=""
retry_count=0
max_retries=60
while [ $retry_count -lt $max_retries ]; do
  describe_result=$(syncerctl_restore_exec backup status --op-id "$backup_name")
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

# Trigger restore via syncerctl on the config-server/replicaset primary. For
# physical restores syncer returns an empty op_id immediately; the actual op_id
# is set on the restore-coord ConfigMap once the leader starts PBM.
echo "INFO: Starting restore via syncerctl..."
restore_result=$(syncerctl_restore_start "$backup_name" --replset-remapping "$mappings")
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
  restore_status_result=$(syncerctl_restore_status "$restore_name")
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

echo "INFO: Restore completed."
