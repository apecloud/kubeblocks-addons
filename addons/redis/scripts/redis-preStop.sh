#!/bin/sh
set -e
if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
  acl_save_command="redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_DEFAULT_PASSWORD acl save"
else
  acl_save_command="redis-cli -h 127.0.0.1 -p 6379 acl save"
fi
echo "acl save command: $acl_save_command" | sed "s/$REDIS_DEFAULT_PASSWORD/********/g"
if output=$($acl_save_command 2>&1); then
  echo "acl save command executed successfully: $output"
else
  echo "failed to execute acl save command: $output"
  exit 1
fi