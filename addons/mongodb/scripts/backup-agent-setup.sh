#!/bin/bash
# shellcheck disable=SC2086

export PATH=$PBM_DATA_MOUNT_POINT/tmp/bin:$PATH

wait_interval=5
while true; do
    cluster_json=$(kubectl get clusters.apps.kubeblocks.io ${KB_CLUSTER_NAME} -n ${KB_NAMESPACE} -o json 2>&1)
    kubectl_get_exit_code=$?
    if [ "$kubectl_get_exit_code" -ne 0 ]; then
        echo "INFO: Cluster ${KB_CLUSTER_NAME} not found, sleep $wait_interval second and retry..."
        sleep $wait_interval
        continue
    fi

    restore_from_backup=$(echo "$cluster_json" | jq -r '.metadata.annotations["kubeblocks.io/restore-from-backup"] // empty')
    if [ -z "$restore_from_backup" ]; then
        echo "INFO: No restore-from-backup annotation, do not need to restore."
        break
    else
        echo "INFO: Waiting for restore completion..."
        sleep $wait_interval
    fi
done

exec pbm-agent-entrypoint
