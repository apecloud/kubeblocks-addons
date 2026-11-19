#!/bin/sh
set -eu

: "${PGBOUNCER_ADMIN_USERNAME:?management username is required}"
: "${PGBOUNCER_ADMIN_PASSWORD:?management password is required}"
: "${CURRENT_POD_IP:?local pod address is required}"

# KubeBlocks waits for this config volume to contain the new projection before
# invoking the file action. RELOAD rereads the mounted %include on each replica.
export PGCONNECT_TIMEOUT=3
export PGPASSWORD="$PGBOUNCER_ADMIN_PASSWORD"
exec timeout -s KILL 5 psql --no-password --username="$PGBOUNCER_ADMIN_USERNAME" \
  --host="$CURRENT_POD_IP" --port=6432 --dbname=pgbouncer \
  --set=ON_ERROR_STOP=1 --command=RELOAD
