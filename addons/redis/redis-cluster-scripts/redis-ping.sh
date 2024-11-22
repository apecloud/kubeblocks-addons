#!/bin/sh

set -e

if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
  cmd="redis-cli -h localhost -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD ping"
else
  cmd="redis-cli -h localhost -p $SERVICE_PORT ping"
fi

response=$($cmd)
status=$?
if [ "$response" != "PONG" ] || [ $status -ne 0 ]; then
  echo "$response"
  exit 1
fi
echo "redis cluster server is running."