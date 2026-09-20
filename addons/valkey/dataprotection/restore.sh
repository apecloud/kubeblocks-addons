#!/bin/bash
# restore.sh — prepareData phase: extract the backup archive into DATA_DIR.
#
# Runs as an init container before the Valkey pod starts.  DATA_DIR must be
# empty (or contain only the .kb-data-protection placeholder) to prevent
# accidentally overwriting a running cluster.  When DP_RESTORE_KEY_PATTERNS is
# set, switch-data-dir.sh (concatenated before this file) has already pointed
# DATA_DIR at ${DATA_DIR}/.restore_keys, so the full archive is staged there
# for the postReady key-migration job instead of the real data directory.
#
# Unlike the previous valkey-specific version there is no AOF seeding: the
# backup archives the whole data directory (including appendonlydir/ when
# appendonly is enabled), so extracting it reproduces the exact on-disk state
# the engine expects.

set -e
set -o pipefail

if [ -n "${DP_DATASAFED_BIN_PATH}" ]; then export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"; fi
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

mkdir -p "${DATA_DIR}"

# Safety check: refuse to restore into a non-empty data directory.
# Use -maxdepth 1 to check for any real data entry directly inside DATA_DIR.
placeholder="${DATA_DIR}/.kb-data-protection"
unexpected_entries=$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name ".kb-data-protection" ! -name "lost+found")
if [ -n "${unexpected_entries}" ]; then
  echo "ERROR: ${DATA_DIR} is not empty. Remove all data before restoring." >&2
  exit 1
fi
if [ -e "${placeholder}" ] && [ ! -f "${placeholder}" ]; then
  echo "ERROR: ${placeholder} exists but is not a file." >&2
  exit 1
fi
touch "${placeholder}"

backupFile="${DP_BACKUP_NAME}.tar.zst"
if [ "$(datasafed list "${backupFile}" 2>/dev/null)" = "${backupFile}" ]; then
  echo "INFO: Restoring from ${backupFile}..."
  datasafed pull -d zstd-fastest "${backupFile}" - | tar -xvf - -C "${DATA_DIR}"
elif [ "$(datasafed list valkey-offline.tar 2>/dev/null)" = "valkey-offline.tar" ]; then
  echo "INFO: Restoring from valkey-offline.tar..."
  datasafed pull valkey-offline.tar - | tar -xvf - -C "${DATA_DIR}"
else
  echo "INFO: Restoring from ${DP_BACKUP_NAME}.tar.gz..."
  datasafed pull "${DP_BACKUP_NAME}.tar.gz" - | tar -xzvf - -C "${DATA_DIR}"
fi

rm -rf "${placeholder}" && sync
echo "INFO: Restore complete."
