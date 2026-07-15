#!/bin/bash

# When doing point-in-time recovery for deployments with sharded collections, PBM only writes data to existing ones and does not support creating new collections.
# Therefore, whenever you create a new sharded collection, make a new backup for it to be included there. Ref: https://docs.percona.com/percona-backup-mongodb/usage/pitr-physical.html#post-restore-steps
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:${MOUNT_DIR}/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_pbm_backup_exit EXIT
run_pbm_pitr_backup
