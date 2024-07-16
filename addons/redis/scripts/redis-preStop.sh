#!/bin/sh
set -e
if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
  redis-cli -h 127.0.0.1 -p 6379 -a "$REDIS_DEFAULT_PASSWORD" acl save
  echo "redis acl save with default password succeeded!"
else
  redis-cli -h 127.0.0.1 -p 6379 acl save
  echo "redis acl save succeeded!"
fi
