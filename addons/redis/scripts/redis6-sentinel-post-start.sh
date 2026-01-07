#!/bin/sh

set -e

# set default user password and replication user password
if [ -n "$SENTINEL_PASSWORD" ]; then
  until redis-cli -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT ping; do sleep 1; done
  redis-cli -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT $REDIS_CLI_TLS_CMD ACL SETUSER $SENTINEL_USER ON \>$SENTINEL_PASSWORD allchannels +@all
  redis-cli -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD $REDIS_CLI_TLS_CMD ACL SAVE
  echo "redis sentinel user and password set successfully."
fi