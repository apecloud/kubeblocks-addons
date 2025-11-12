#!/bin/bash
set -euo pipefail

HOST="127.0.0.1"
SCHEME="http"
PORT="${CLICKHOUSE_HTTP_PORT:-8123}"

wget_args=(
  --spider
  -q
  -T 3
  --tries=1
)

if [[ "${TLS_ENABLED:-false}" == "true" ]]; then
  SCHEME="https"
  PORT="${CLICKHOUSE_HTTPS_PORT:-8443}"
  wget_args+=(--no-check-certificate)
fi

endpoint="${SCHEME}://${HOST}:${PORT}/ping"

if ! /shared-tools/wget "${wget_args[@]}" "${endpoint}"; then
  echo "Readiness probe failed accessing ${endpoint}" >&2
  exit 1
fi
