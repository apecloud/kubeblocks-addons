#!/bin/bash
set -e
set -o pipefail

export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

# shellcheck source=common-scripts.sh
if ! command -v set_backup_config_env >/dev/null 2>&1; then
  . "$(dirname "$0")/common-scripts.sh"
fi

set_backup_config_env

echo "INFO: Ensuring restore-coord ConfigMap exists with storage config."

# The canonical expected-member list is discovered by the syncer dp-leader from
# Kubernetes pod labels, because CMPD vars do not reliably propagate into
# restore ActionSet job containers. We pass only the local target pod (if known)
# as a fallback so the leader has at least one member to wait on.
expected_members="${DP_TARGET_POD_NAME:-}"

storage_config=$(pbm_storage_config_yaml)
ensure_restore_coord "$expected_members" "$storage_config"

echo "INFO: Restore coordination prepared."
