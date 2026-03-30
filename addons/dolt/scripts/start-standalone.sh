#!/bin/sh
set -eu

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
SERVER_CONFIG="${DATA_DIR}/.server-config.yaml"

# Render the config template to the directory the official entrypoint reads from.
mkdir -p /etc/dolt/servercfg.d/config.yaml

sed \
  -e "s|\${DATA_DIR}|${DATA_DIR}|g" \
  /config/config.yaml > "${SERVER_CONFIG}"

# Hand off to the official docker-entrypoint.sh, which handles:
#   - server startup and readiness probing (dolt_server_initializer)
#   - root user host config via DOLT_ROOT_HOST
#   - optional user/db creation via DOLT_USER / DOLT_PASSWORD / DOLT_DATABASE
#   - init scripts in /docker-entrypoint-initdb.d/
#   - idempotent re-runs via $CONTAINER_DATA_DIR/.init_completed
#   - signal handling and wait
exec /scripts/docker-entrypoint.sh --config="${SERVER_CONFIG}"
