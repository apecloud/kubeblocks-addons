#!/bin/bash

set -ex

save_acl() {
  set +x
  if [ -n "$REDIS_DEFAULT_PASSWORD" ]; then
    redis-cli -h 127.0.0.1 -p $SERVICE_PORT -a "$REDIS_DEFAULT_PASSWORD" acl save
  else
    redis-cli -h 127.0.0.1 -p $SERVICE_PORT acl save
  fi
  set -x
  echo "acl save command executed successfully"
}

# main
save_acl