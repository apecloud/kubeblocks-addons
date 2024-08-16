#!/bin/bash
set -e
if [ ! -z "$REDIS_DEFAULT_PASSWORD" ]; then
  acl_save_command="redis-cli -h 127.0.0.1 -p 6379 -a $REDIS_DEFAULT_PASSWORD acl save"
  logging_mask_acl_save_command="${acl_save_command/$REDIS_DEFAULT_PASSWORD/********}"
else
  acl_save_command="redis-cli -h 127.0.0.1 -p 6379 acl save"
  logging_mask_acl_save_command="$acl_save_command"
fi
echo "acl save command: $logging_mask_acl_save_command"
if output=$($acl_save_command 2>&1); then
  echo "acl save command executed successfully: $output"
else
  echo "failed to execute acl save command: $output"
  exit 1
fi