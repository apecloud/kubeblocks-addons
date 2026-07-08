#!/bin/bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/rabbitmq}"
TARGET_POD_NAME="${DP_TARGET_POD_NAME:?DP_TARGET_POD_NAME is required}"
ARCHIVE_NAME="${TARGET_POD_NAME}.tar.zst"

[ -n "${DP_DATASAFED_BIN_PATH:-}" ] && export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required}"

mkdir -p "${DATA_DIR}"
placeholder="${DATA_DIR}/.kb-data-protection"
existing_entries="$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name '.kb-data-protection' ! -name 'lost+found' -print -quit)"
if [ -n "${existing_entries}" ]; then
  echo "ERROR: ${DATA_DIR} is not empty; refusing to overwrite existing RabbitMQ data" >&2
  exit 1
fi

touch "${placeholder}"
if ! datasafed list "${ARCHIVE_NAME}" 2>/dev/null | grep -qF "${ARCHIVE_NAME}"; then
  echo "ERROR: backup archive ${ARCHIVE_NAME} not found in repository" >&2
  exit 1
fi

echo "INFO: restoring RabbitMQ data archive ${ARCHIVE_NAME} into ${DATA_DIR}"
datasafed pull -d zstd-fastest "${ARCHIVE_NAME}" - | tar -xf - -C "${DATA_DIR}"
rm -f "${placeholder}"
chown -R rabbitmq:rabbitmq "${DATA_DIR}" || true
sync
echo "INFO: restore prepareData completed"
