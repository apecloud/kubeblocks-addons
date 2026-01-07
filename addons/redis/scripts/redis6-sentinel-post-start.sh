#!/bin/sh

set -e

# set default user password and replication user password
if [ -n "$SENTINEL_PASSWORD" ]; then
  until redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT ping; do sleep 1; done
  redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT ACL SETUSER $SENTINEL_USER ON \>$SENTINEL_PASSWORD allchannels +@all
  redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD ACL SAVE
  echo "redis sentinel user and password set successfully."
fi