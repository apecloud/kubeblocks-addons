#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -e;
}

acl_set_user_for_redis6_sentinel() {
  set -e
  # set default user password and replication user password
  if [ -n "$SENTINEL_PASSWORD" ]; then
    # shellcheck disable=SC2086
    until redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT ping; do sleep 1; done
    # shellcheck disable=SC2086
    redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT ACL SETUSER $SENTINEL_USER ON \>$SENTINEL_PASSWORD allchannels +@all
    # shellcheck disable=SC2086
    redis-cli $REDIS_CLI_TLS_CMD -h 127.0.0.1 -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD ACL SAVE
    echo "redis sentinel user and password set successfully."
  fi
}

${__SOURCED__:+false} : || return 0

acl_set_user_for_redis6_sentinel
