#!/usr/bin/env bash
#
# Apply one KubeBlocks Configure parameter to YashanDB persisted config files.

set -euo pipefail

PARAM_NAME="${1:?missing param name}"
PARAM_VALUE="${2:?missing param value}"
YASDB_MOUNT_HOME="${YASDB_MOUNT_HOME:-/home/yashan/mydb}"
YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"

# 2026-06-22 Reason: YashanDB Stage 5A supports only static install.ini parameters; Purpose: reject unrelated environment variables from the KubeBlocks reconfigure action.
case "${PARAM_NAME}" in
  REDO_FILE_SIZE | REDO_FILE_NUM | INSTALL_SIMPLE_SCHEMA_SALES | NLS_CHARACTERSET | LISTEN_ADDR | DB_BLOCK_SIZE | DATA_BUFFER_SIZE | SHARE_POOL_SIZE | WORK_AREA_POOL_SIZE | LARGE_POOL_SIZE | REDO_BUFFER_SIZE | UNDO_RETENTION | OPEN_CURSORS | MAX_SESSIONS | RUN_LOG_LEVEL | NODE_ID)
    ;;
  *)
    echo "skip unsupported YashanDB parameter: ${PARAM_NAME}"
    exit 0
    ;;
esac

if [ ! -f "${YASDB_TEMP_FILE}" ]; then
  echo "YashanDB temp config is missing: ${YASDB_TEMP_FILE}" >&2
  exit 1
fi

# shellcheck disable=SC1090
source "${YASDB_TEMP_FILE}"

YASDB_INSTALL_FILE="${YASDB_INSTALL_FILE:-${YASDB_MOUNT_HOME}/install.ini}"
YASDB_CONFIG="${YASDB_DATA}/config/yasdb.ini"

update_key_value_file() {
  local file="$1"
  local key="$2"
  local value="$3"

  if [ ! -f "${file}" ]; then
    echo "config file is missing: ${file}" >&2
    return 1
  fi

  if grep -qE "^${key}=" "${file}"; then
    sed -i "s|^${key}=.*|${key}=${value}|" "${file}"
  else
    printf '%s=%s\n' "${key}" "${value}" >>"${file}"
  fi
}

# 2026-06-22 Reason: install.ini remains the PVC-level source for future restarts, while yasdb.ini is the runtime config generated from the instance section; Purpose: keep both files aligned without claiming dynamic ALTER SYSTEM reload.
update_key_value_file "${YASDB_INSTALL_FILE}" "${PARAM_NAME}" "${PARAM_VALUE}"
if [ -f "${YASDB_CONFIG}" ]; then
  update_key_value_file "${YASDB_CONFIG}" "${PARAM_NAME}" "${PARAM_VALUE}"
fi
update_key_value_file "${YASDB_TEMP_FILE}" "${PARAM_NAME}" "${PARAM_VALUE}"

echo "updated YashanDB parameter ${PARAM_NAME}"
