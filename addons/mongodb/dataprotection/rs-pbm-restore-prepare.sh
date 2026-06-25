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

echo "INFO: Ensuring restore-coord ConfigMap exists with expected members and storage config."

expected_members=$(fqdns_to_pod_names "${MONGODB_POD_FQDN_LIST:-}")
if [ -z "$expected_members" ] && [ -n "${DP_TARGET_POD_NAME:-}" ]; then
  expected_members="$DP_TARGET_POD_NAME"
fi
if [ -z "$expected_members" ]; then
  echo "ERROR: cannot determine expected members for restore-coord ConfigMap" >&2
  exit 1
fi

storage_config=$(pbm_storage_config_yaml)
ensure_restore_coord "$expected_members" "$storage_config"

echo "INFO: Restore coordination prepared."
