#!/bin/bash
set -e
set -o pipefail

# backup-for-rebuild.sh — backupData command of the valkey-for-rebuild-instance
# ActionSet (port of the redis addon's backup_for_rebuild.sh).
#
# The rebuild-instance flow (KB RebuildFrom) recreates an instance from this
# "backup", which intentionally carries NO dataset: the rebuilt pod re-syncs
# the data from the primary through normal replication.  What must survive the
# rebuild is the ACL file (users.acl) so the rebuilt pod authenticates exactly
# like the old one.  Valkey has no cluster mode, so redis's nodes.conf push is
# dropped here.

# if the script exits with a non-zero exit code, touch a file to indicate that the backup failed,
# the sync progress container will check this file and exit if it exists
function handle_exit() {
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "failed with exit code $exit_code"
        touch "${DP_BACKUP_INFO_FILE}.exit"
        exit 1
    fi
}
trap handle_exit EXIT

if [ -n "${DP_DATASAFED_BIN_PATH}" ]; then
  export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
fi
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"
cd "${DATA_DIR}"
datasafed push ./users.acl "users.acl"
echo "INFO: save data file successfully"
TOTAL_SIZE=$(datasafed stat / | grep TotalSize | awk '{print $2}')
echo "{\"totalSize\":\"$TOTAL_SIZE\"}" >"${DP_BACKUP_INFO_FILE}" && sync
