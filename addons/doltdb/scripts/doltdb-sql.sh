#!/bin/sh
set -eu

: "${DOLT_ROOT_PASSWORD:?DOLT_ROOT_PASSWORD is required}"

query="${1:-}"
database="${DOLT_PROBE_DATABASE:-${DOLT_DATABASE:-}}"

set -- \
  --host="${DOLT_SQL_HOST:-127.0.0.1}" \
  --port="${DOLT_SQL_PORT:-3306}" \
  --user=root \
  --password="${DOLT_ROOT_PASSWORD}"

if [ "${TLS_ENABLED:-false}" = "true" ]; then
  tls_ca="${DOLT_TLS_CA_FILE:-${TLS_MOUNT_PATH:-/etc/pki/tls}/ca.crt}"
  export SSL_CERT_FILE="$tls_ca"
else
  set -- "$@" --no-tls
fi

if [ "${DOLT_NO_DATABASE:-false}" != "true" ] && [ -n "$database" ]; then
  set -- "$@" --use-db="$database"
fi

if [ -n "$query" ]; then
  exec dolt "$@" sql "--query=$query" --result-format=csv
fi

exec dolt "$@" sql --result-format=csv
