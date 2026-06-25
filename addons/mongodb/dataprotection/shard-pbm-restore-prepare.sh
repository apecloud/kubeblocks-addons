#!/bin/bash
set -e
set -o pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

# shellcheck source=common-scripts.sh
if ! command -v ensure_restore_coord >/dev/null 2>&1; then
  . "$(dirname "$0")/common-scripts.sh"
fi

set_backup_config_env

# Ensure the restore-coord ConfigMap exists with the storage config. The
# canonical expected-member list is discovered by the syncer dp-leader from
# Kubernetes pod labels, because CMPD vars do not reliably propagate into
# restore ActionSet job containers.
#
# Mongos readiness and balancer/autosplit disable/enable are now driven by the
# syncer config-server primary inside the physical/PITR restore flow, where the
# main container has access to MONGOS_INTERNAL_HOST/PORT.
echo "INFO: Ensuring restore-coord ConfigMap exists with storage config."

storage_config=$(pbm_storage_config_yaml)
ensure_restore_coord "" "$storage_config"

echo "INFO: Restore coordination prepared."
