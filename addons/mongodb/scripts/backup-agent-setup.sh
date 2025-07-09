#!/bin/bash
# shellcheck disable=SC2086

export PATH=$PBM_DATA_MOUNT_POINT/tmp/bin:$PATH

# shellcheck disable=SC1091
. "/scripts/mongodb-common.sh"

wait_restore_completion_by_cluster_cr

exec pbm-agent-entrypoint
