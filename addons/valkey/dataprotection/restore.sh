#!/bin/bash
# restore.sh — prepareData phase: extract backup archive into DATA_DIR.
#
# Runs as an init container before the Valkey pod starts.
# DATA_DIR must be empty (or contain only the .kb-data-protection placeholder)
# to prevent accidentally overwriting a running cluster.

set -e
set -o pipefail

[ -n "${DP_DATASAFED_BIN_PATH}" ] && export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

mkdir -p "${DATA_DIR}"

# Safety check: refuse to restore into a non-empty data directory.
# Use -maxdepth 1 to check for any entry (file or directory) directly inside DATA_DIR.
placeholder="${DATA_DIR}/.kb-data-protection"
existing_entries=$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1)
if [ -n "${existing_entries}" ] && [ ! -f "${placeholder}" ]; then
  echo "ERROR: ${DATA_DIR} is not empty. Remove all data before restoring." >&2
  exit 1
fi
touch "${placeholder}"

archive="${DP_BACKUP_NAME}.tar.zst"
if datasafed list "${archive}" 2>/dev/null | grep -qF "${archive}"; then
  echo "INFO: Restoring from ${archive}..."
  datasafed pull -d zstd-fastest "${archive}" - | tar -xvf - -C "${DATA_DIR}"
else
  echo "ERROR: backup archive '${archive}' not found in repository." >&2
  exit 1
fi

rm -f "${placeholder}" && sync
echo "INFO: Restore complete."
