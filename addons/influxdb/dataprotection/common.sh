#!/usr/bin/env bash

set -euo pipefail
# Never enable shell tracing: credentials contain the operator token.
INFLUX_TOKEN="${DP_DB_PASSWORD:-${INFLUXDB_ADMIN_USER_TOKEN:-${INFLUXDB_ADMIN_PASSWORD:-${INFLUXDB_ADMIN_USER_PASSWORD:-}}}}"
: "${DP_DB_HOST:?}" "${INFLUX_TOKEN:?}" "${DP_BACKUP_BASE_PATH:?}"
export PATH="${PATH}:${DP_DATASAFED_BIN_PATH:?}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"
export INFLUX_HOST="http://${DP_DB_HOST}:${DP_DB_PORT:-8086}"
export INFLUX_TOKEN
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

# The catalog uses NUL-terminated organization and bucket names in pairs.
read_bucket_selection() {
  local selected_org selected_bucket
  bucket_orgs=()
  bucket_names=()
  while IFS= read -r -d '' selected_org || [[ -n $selected_org ]]; do
    if [[ -z $selected_org ]] || ! IFS= read -r -d '' selected_bucket || [[ -z $selected_bucket ]]; then
      echo "Invalid InfluxDB bucket selection" >&2
      return 1
    fi
    bucket_orgs+=("$selected_org")
    bucket_names+=("$selected_bucket")
  done < "$1"
  if [[ -z ${bucket_names[0]:-} ]]; then
    echo "Select at least one InfluxDB bucket" >&2
    return 1
  fi
}

write_bucket_selection() {
  if [[ -z ${buckets:-} ]]; then
    echo "Select at least one InfluxDB bucket using the buckets parameter" >&2
    return 1
  fi

  # Parse the qualified bucket list produced by the level 1 mapping.
  local remaining=$buckets
  local pair='^"([^"]+)"/"([^"]+)"'
  while [[ $remaining =~ $pair ]]; do
    printf '%s\0%s\0' "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    remaining=${remaining:${#BASH_REMATCH[0]}}
    [[ -n $remaining ]] || return 0
    [[ $remaining == ,* ]] || break
    remaining=${remaining:1}
  done > "$1"
  echo 'Invalid buckets parameter: expected comma-separated "org"/"bucket" entries' >&2
  return 1
}

bucket_key() {
  local checksum
  checksum=$(printf '%s\0%s\0' "$1" "$2" | sha256sum) || return
  printf '%s' "${checksum%% *}"
}
