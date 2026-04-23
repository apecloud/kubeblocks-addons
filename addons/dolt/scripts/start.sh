#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
INIT_COMPLETED="${DATA_DIR}/.init_completed"
SERVER_CONFIG="${DATA_DIR}/.server-config.yaml"
REMOTES_API_PORT="${REMOTES_API_PORT:-50051}"

if [ -f "${INIT_COMPLETED}" ]; then
  # Data dir already initialized: reuse persisted server config (roles/remotes are in data).
  :
else
  POD_NAME="${CURRENT_POD_NAME:-}"
  if [ -z "${POD_NAME}" ]; then
    echo "CURRENT_POD_NAME is required on first start" >&2
    exit 1
  fi

  POD_BASENAME="${POD_NAME%-*}"
  POD_ORDINAL="${POD_NAME##*-}"

  if [ "${POD_ORDINAL}" = "0" ]; then
    BOOTSTRAP_ROLE="primary"
    STANDBY_HOST="${POD_BASENAME}-1"
  else
    BOOTSTRAP_ROLE="standby"
    STANDBY_HOST="${POD_BASENAME}-0"
  fi

  HEADLESS_SERVICE_NAME="${POD_BASENAME}-headless"

  sed \
    -e "s|\${BOOTSTRAP_ROLE}|${BOOTSTRAP_ROLE}|g" \
    -e "s|\${STANDBY_HOST}|${STANDBY_HOST}|g" \
    -e "s|\${HEADLESS_SERVICE_NAME}|${HEADLESS_SERVICE_NAME}|g" \
    -e "s|\${REMOTES_API_PORT}|${REMOTES_API_PORT}|g" \
    -e "s|\${DATA_DIR}|${DATA_DIR}|g" \
    /config/config.yaml > "${SERVER_CONFIG}"
fi

# Same as start-standalone.sh: official entrypoint handles server readiness, root host,
# optional env users/db, initdb.d, .init_completed, signals, and wait.
exec /scripts/docker-entrypoint.sh --config="${SERVER_CONFIG}"
