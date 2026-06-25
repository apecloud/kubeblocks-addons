#!/bin/bash
# shellcheck disable=SC2086

export PATH=$PBM_DATA_MOUNT_POINT/tmp/bin:$PATH

# shellcheck disable=SC1091
. "/scripts/mongodb-common.sh"

# For normal clusters, start the backup agent immediately. For restore clusters,
# wait until the restore is complete so the temporary pbm-agent started by the
# mongodb container owns the restore.
cluster_json=$(kubectl get clusters.apps.kubeblocks.io "${CLUSTER_NAME}" -n "${CLUSTER_NAMESPACE}" -o json 2>/dev/null || true)
if ! is_restore_cluster "$cluster_json"; then
  echo "INFO: Not a restore cluster, starting backup agent immediately."
  exec pbm-agent-entrypoint
fi

echo "INFO: Restore cluster detected, waiting for restore completion..."
wait_restore_completion_by_cluster_cr

exec pbm-agent-entrypoint
