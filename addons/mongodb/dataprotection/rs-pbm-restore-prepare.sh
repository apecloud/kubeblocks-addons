#!/bin/bash
set -e
set -o pipefail

mkdir -p ${MOUNT_DIR}/tmp

# Materialize PBM storage config into the shared data volume before the restore
# cluster pods start. The mongodb container startup path will apply this config
# to the local mongod before starting the temporary pbm-agent, preventing the
# agent from resyncing against the source cluster's prefix before storage config
# is available.
export PATH="$PATH:$DP_DATASAFED_BIN_PATH"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

# shellcheck source=common-scripts.sh
. "$(dirname "$0")/common-scripts.sh"

set_backup_config_env
PBM_STORAGE_CONFIG_PATH="${MOUNT_DIR}/tmp/pbm_storage_config.yaml"
echo "INFO: Writing PBM storage config to ${PBM_STORAGE_CONFIG_PATH}"
write_pbm_storage_config_yaml "$PBM_STORAGE_CONFIG_PATH"
echo "INFO: PBM storage config materialized."

cd ${MOUNT_DIR}/tmp && touch mongodb_pbm.backup
