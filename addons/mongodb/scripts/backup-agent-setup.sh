#!/bin/bash
# shellcheck disable=SC2086

export PATH=$PBM_DATA_MOUNT_POINT/tmp/bin:$PATH

RESTORE_FLAG="${PBM_RESTORE_FLAG_PATH:-${PBM_DATA_MOUNT_POINT}/tmp/mongodb_pbm.backup}"

# For normal clusters, start the backup agent immediately. For restore clusters,
# wait until the restore flag (created by prepareData / setup script) is removed,
# so the temporary pbm-agent started by the mongodb container owns the restore.
for i in $(seq 1 10); do
  if [ -f "$RESTORE_FLAG" ]; then
    break
  fi
  sleep 1
done

if [ ! -f "$RESTORE_FLAG" ]; then
  echo "INFO: No restore flag, starting backup agent immediately."
  exec pbm-agent-entrypoint
fi

echo "INFO: Restore flag detected, waiting for restore completion..."
while [ -f "$RESTORE_FLAG" ]; do
  echo "Waiting for restore..."
  sleep 5
done

exec pbm-agent-entrypoint
