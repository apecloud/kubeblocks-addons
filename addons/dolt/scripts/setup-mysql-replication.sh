#!/bin/bash
set -eo pipefail

# Configures Dolt as a MySQL binlog replica.
# Expects env vars: MYSQL_SOURCE_HOST, MYSQL_SOURCE_PORT
# Optional env vars: MYSQL_SOURCE_USER, MYSQL_SOURCE_PASSWORD, DOLT_REPLICA_SERVER_ID

SOURCE_HOST="${MYSQL_SOURCE_HOST}"
SOURCE_PORT="${MYSQL_SOURCE_PORT:-3306}"
SOURCE_USER="${MYSQL_SOURCE_USER:-root}"
SOURCE_PASSWORD="${MYSQL_SOURCE_PASSWORD:-}"
SERVER_ID="${DOLT_REPLICA_SERVER_ID:-10}"

dolt_sql() {
  dolt --host 127.0.0.1 --port 3306 --no-tls sql -q "$1"
}

echo "Configuring Dolt as MySQL binlog replica of ${SOURCE_HOST}:${SOURCE_PORT}..."

dolt_sql "SET @@PERSIST.server_id = ${SERVER_ID};"

if [ -n "${SOURCE_PASSWORD}" ]; then
  dolt_sql "CHANGE REPLICATION SOURCE TO SOURCE_HOST='${SOURCE_HOST}', SOURCE_USER='${SOURCE_USER}', SOURCE_PASSWORD='${SOURCE_PASSWORD}', SOURCE_PORT=${SOURCE_PORT};"
else
  dolt_sql "CHANGE REPLICATION SOURCE TO SOURCE_HOST='${SOURCE_HOST}', SOURCE_USER='${SOURCE_USER}', SOURCE_PORT=${SOURCE_PORT};"
fi

dolt_sql "START REPLICA;"

echo "MySQL binlog replication started. Source: ${SOURCE_HOST}:${SOURCE_PORT}"
