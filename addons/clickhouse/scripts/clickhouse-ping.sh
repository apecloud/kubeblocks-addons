#!/bin/bash
set -euo pipefail

TLS_MOUNT_PATH="/etc/pki/tls"
READINESS_PROBE_TIMEOUT="${READINESS_PROBE_TIMEOUT:-3}"
HOST="127.0.0.1"
SCHEME="http"
PORT="${CLICKHOUSE_HTTP_PORT:-8123}"

curl_args=(
  --silent
  --show-error
  --fail
  --connect-timeout "${READINESS_PROBE_TIMEOUT}"
  --max-time "${READINESS_PROBE_TIMEOUT}"
)

if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
  SCHEME="https"
  PORT="${CLICKHOUSE_HTTPS_PORT:-8443}"
  if [[ -f "${TLS_MOUNT_PATH}/ca.pem" ]]; then
    curl_args+=(--cacert "${TLS_MOUNT_PATH}/ca.pem")
  fi
  if [[ -f "${TLS_MOUNT_PATH}/cert.pem" && -f "${TLS_MOUNT_PATH}/key.pem" ]]; then
    curl_args+=(--cert "${TLS_MOUNT_PATH}/cert.pem" --key "${TLS_MOUNT_PATH}/key.pem")
  fi
fi

endpoint="${SCHEME}://${HOST}:${PORT}/ping"

if ! curl "${curl_args[@]}" "${endpoint}" >/dev/null; then
  echo "Readiness probe failed accessing ${endpoint}" >&2
  exit 1
fi
