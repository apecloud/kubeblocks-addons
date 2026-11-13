#!/usr/bin/env bash

set -euo pipefail
# Never enable shell tracing: DP_DB_PASSWORD is the operator token.
: "${DP_DB_HOST:?}" "${DP_DB_PASSWORD:?}" "${DP_BACKUP_BASE_PATH:?}"
export PATH="${PATH}:${DP_DATASAFED_BIN_PATH:?}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"
export INFLUX_HOST="http://${DP_DB_HOST}:${DP_DB_PORT:-8086}"
export INFLUX_TOKEN="${DP_DB_PASSWORD}"
umask 077
work_dir=$(mktemp -d)
# Keep CLI configuration (which can contain tokens) in the disposable directory.
export INFLUX_CONFIGS_PATH="${work_dir}/configs"
cleanup() {
  local status=$?
  if [[ $status -ne 0 && -n ${DP_BACKUP_INFO_FILE:-} ]]; then
    touch "${DP_BACKUP_INFO_FILE}.exit"
  fi
  rm -rf "${work_dir}"
  exit "$status"
}
trap cleanup EXIT
