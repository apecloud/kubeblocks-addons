#!/bin/bash

# For PITR with PBM physical backups, create a fresh base backup whenever new collections must be included by restore.
# PBM only writes data to existing collections and does not support creating new ones during PITR, so a new
# (sharded) collection needs a new backup to be included. Shared by replica-set and sharded deployments.
# Ref: https://docs.percona.com/percona-backup-mongodb/usage/pitr-physical.html#post-restore-steps
set -e
set -o pipefail
export PATH="$PATH:$DP_DATASAFED_BIN_PATH:${MOUNT_DIR}/tmp/bin"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

trap handle_pbm_backup_exit EXIT
run_pbm_pitr_backup
