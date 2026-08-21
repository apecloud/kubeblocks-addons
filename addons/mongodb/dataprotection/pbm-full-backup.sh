#!/bin/bash
set -e
set -o pipefail
# syncerctl is delivered through the target data PVC at ${MOUNT_DIR}/tmp/bin.
export PATH="$PATH:${MOUNT_DIR}/tmp/bin"

trap handle_pbm_backup_exit EXIT
run_pbm_full_backup
