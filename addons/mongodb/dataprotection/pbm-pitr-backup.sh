#!/bin/bash

# For PITR with PBM physical backups, create a fresh base backup whenever new collections must be included by restore.
# PBM only writes data to existing collections and does not support creating new ones during PITR, so a new
# (sharded) collection needs a new backup to be included. Shared by replica-set and sharded deployments.
# Ref: https://docs.percona.com/percona-backup-mongodb/usage/pitr-physical.html#post-restore-steps
set -e
set -o pipefail
# syncerctl is delivered through the target data PVC at ${MOUNT_DIR}/tmp/bin.
export PATH="$PATH:${MOUNT_DIR}/tmp/bin"

trap handle_pbm_backup_exit EXIT
run_pbm_pitr_backup
