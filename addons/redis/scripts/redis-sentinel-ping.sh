#!/bin/sh

set -e

if [ -n "$SENTINEL_PASSWORD" ]; then
  cmd="redis-cli -h localhost -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD ping"
else
  cmd="redis-cli -h localhost -p $SENTINEL_SERVICE_PORT ping"
fi

response=$($cmd)
status=$?
if [ "$response" != "PONG" ] || [ $status -ne 0 ]; then
  echo "$response"
  exit 1
fi
echo "redis sentinel is running."