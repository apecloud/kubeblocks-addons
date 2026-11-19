#!/bin/sh
set -eu

export PGCONNECT_TIMEOUT=3
case "$PGBOUNCER_BACKEND_ROLE" in
  rw) expected=primary ;;
  ro) expected=replica ;;
  *) exit 1 ;;
esac

backend="$(
  # Bound SQL queueing as well as connection setup, within the five-second probe budget.
  PGPASSWORD="$POSTGRESQL_PASSWORD" timeout -s KILL 2 psql --no-password --username="$POSTGRESQL_USERNAME" \
    --host="$CURRENT_POD_IP" --port=6432 --dbname=postgres \
    --tuples-only --no-align --set=ON_ERROR_STOP=1 \
    --command="SELECT CASE WHEN pg_is_in_recovery() THEN 'replica' WHEN current_setting('transaction_read_only') = 'off' THEN 'primary' ELSE 'read-only' END"
)"

if [ "$backend" = "$expected" ]; then
  exit 0
fi

if [ "$backend" = "primary" ] || [ "$backend" = "replica" ] ||
  { [ "$PGBOUNCER_BACKEND_ROLE" = "ro" ] && [ "$backend" = "read-only" ]; }; then
  # Every pool targets the same role Service. Retire stale backend connections
  # when released; occupied session pools remain until their clients disconnect.
  PGPASSWORD="$PGBOUNCER_ADMIN_PASSWORD" timeout -s KILL 2 psql --no-password --username="$PGBOUNCER_ADMIN_USERNAME" \
    --host="$CURRENT_POD_IP" --port=6432 --dbname=pgbouncer \
    --set=ON_ERROR_STOP=1 --command="RECONNECT" > /dev/null
fi

exit 1
