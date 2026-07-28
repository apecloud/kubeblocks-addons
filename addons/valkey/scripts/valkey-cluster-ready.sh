#!/bin/sh

port="${SERVICE_PORT:-6379}"
data_dir="${VALKEY_DATA_DIR:-/data}"
marker="${data_dir}/.kb-valkey-cluster-formed"

run_cli() {
  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}" \
      -a "${VALKEY_DEFAULT_PASSWORD}" ${VALKEY_CLI_TLS_ARGS:-} "$@"
  else
    valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}" \
      ${VALKEY_CLI_TLS_ARGS:-} "$@"
  fi
}

# Before postProvision closes, PING readiness is required so the lifecycle
# action can run without a readiness/postProvision dependency cycle.
response=$(run_cli PING 2>/dev/null) || exit 1
[ "${response}" = "PONG" ] || exit 1
[ -L "${marker}" ] && exit 1
[ ! -e "${marker}" ] && exit 0
[ -f "${marker}" ] || exit 1
[ "$(cat "${marker}" 2>/dev/null)" = "formed" ] || exit 1

info=$(run_cli CLUSTER INFO 2>/dev/null) || exit 1
cluster_info_value() {
  printf '%s\n' "${info}" | awk -F: -v key="$1" '
    $1 == key { gsub(/\r/, "", $2); value=$2; count++ }
    END { if (count != 1 || value == "") exit 1; print value }
  '
}

[ "$(cluster_info_value cluster_state)" = "ok" ] &&
  [ "$(cluster_info_value cluster_slots_assigned)" = "16384" ] &&
  [ "$(cluster_info_value cluster_slots_ok)" = "16384" ] &&
  [ "$(cluster_info_value cluster_slots_pfail)" = "0" ] &&
  [ "$(cluster_info_value cluster_slots_fail)" = "0" ]
