#!/bin/bash
set -e
set -o pipefail
# syncerctl is delivered through the target data PVC at $MOUNT_DIR/tmp/bin.
export PATH="$PATH:$MOUNT_DIR/tmp/bin"

set_backup_config_env

trap handle_restore_exit EXIT
run_pbm_full_restore
