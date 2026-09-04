#!/bin/bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/rabbitmq}"
TARGET_NAME=""

validate_dns_subdomain() {
  local value="$1"
  local label=""
  local -a labels=()

  [ "${#value}" -le 253 ] || return 1
  [[ "${value}" =~ ^[a-z0-9]([-a-z0-9.]*[a-z0-9])?$ ]] || return 1
  IFS='.' read -r -a labels <<< "${value}"
  for label in "${labels[@]}"; do
    [ "${#label}" -le 63 ] || return 1
    [[ "${label}" =~ ^[a-z0-9]([-a-z0-9]*[a-z0-9])?$ ]] || return 1
  done
}

# Backup jobs inject DP_TARGET_POD_NAME. Volume-populator AsDataSource prepareData
# may only inject DP_TARGET_RELATIVE_PATH, either as <pod-name> or
# <target-name>/<pod-name>. DP_BACKUP_BASE_PATH is already scoped to that path,
# so the archive key always uses only the final pod-name segment.
if [ -n "${DP_TARGET_POD_NAME:-}" ]; then
  TARGET_POD_NAME="${DP_TARGET_POD_NAME}"
else
  TARGET_RELATIVE_PATH="${DP_TARGET_RELATIVE_PATH:?DP_TARGET_POD_NAME or DP_TARGET_RELATIVE_PATH is required}"
  case "${TARGET_RELATIVE_PATH}" in
    /*|*/|*/*/*)
      echo "ERROR: DP_TARGET_RELATIVE_PATH must be one pod segment or <target-name>/<target-pod-name>" >&2
      exit 1
      ;;
    */*)
      TARGET_NAME="${TARGET_RELATIVE_PATH%%/*}"
      TARGET_POD_NAME="${TARGET_RELATIVE_PATH##*/}"
      ;;
    *)
      TARGET_POD_NAME="${TARGET_RELATIVE_PATH}"
      ;;
  esac
fi

if [ -n "${TARGET_NAME}" ] && ! validate_dns_subdomain "${TARGET_NAME}"; then
  echo "ERROR: DP_TARGET_RELATIVE_PATH target name must be a valid DNS subdomain" >&2
  exit 1
fi
if ! validate_dns_subdomain "${TARGET_POD_NAME}"; then
  echo "ERROR: restore target pod name must be a valid DNS subdomain" >&2
  exit 1
fi

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
