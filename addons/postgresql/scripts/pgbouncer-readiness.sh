#!/bin/sh
set -eu

export PGPASSWORD="$POSTGRESQL_PASSWORD" PGCONNECT_TIMEOUT=3

backend="$(
  psql --no-password --username="$POSTGRESQL_USERNAME" \
    --host="$CURRENT_POD_IP" --port=6432 --dbname=postgres \
    --tuples-only --no-align --set=ON_ERROR_STOP=1 \
    --command="SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' WHEN current_setting('transaction_read_only') = 'off' THEN 'primary' ELSE 'read-only' END"
)"

if [ "$backend" = "primary" ]; then
  exit 0
fi

if [ "$backend" = "replica" ]; then
  # All database pools use the same primary Service. Its routing may change
  # after a connection has reached the demoted primary; retire those connections
  # when released, and let the next probe verify the new backend.
  psql --no-password --username="$POSTGRESQL_USERNAME" \
    --host="$CURRENT_POD_IP" --port=6432 --dbname=pgbouncer \
    --set=ON_ERROR_STOP=1 --command="RECONNECT" > /dev/null
fi

exit 1
