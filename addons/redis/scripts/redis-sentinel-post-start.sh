#!/bin/sh
set -e
# set default user password and replication user password
if [ -n "$SENTINEL_PASSWORD" ]; then
  until redis-cli -h 127.0.0.1 -p 26379 -a $SENTINEL_PASSWORD ping; do sleep 1; done
  redis-cli -h 127.0.0.1 -p 26379 ACL SETUSER $SENTINEL_USER ON \>$SENTINEL_PASSWORD allchannels +@all
  echo "redis sentinel user and password set successfully."
fi