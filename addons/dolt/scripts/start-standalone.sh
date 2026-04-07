#!/bin/bash
set -eo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/dolt}"
SERVER_CONFIG="${DATA_DIR}/.server-config.yaml"

mkdir -p /etc/dolt/servercfg.d/config.yaml
mkdir -p "${DATA_DIR}/.doltcfg"

sed \
  -e "s|\${DATA_DIR}|${DATA_DIR}|g" \
  /config/config.yaml > "${SERVER_CONFIG}"

# MySQL source is configured — start the entrypoint in background, then
# wait for the server to be ready and configure binlog replication.
/scripts/docker-entrypoint.sh --config="${SERVER_CONFIG}" &
EP_PID=$!

if [ -n "${MYSQL_SOURCE_HOST:-}" ]; then
  until dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "SELECT 1" >/dev/null 2>&1; do
    if ! kill -0 "$EP_PID" 2>/dev/null; then
      echo "Entrypoint exited before server became ready"
      exit 1
    fi
    sleep 2
  done

  /scripts/setup-mysql-replication.sh
fi

wait "$EP_PID"
