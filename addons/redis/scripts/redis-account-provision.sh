#!/bin/bash

ut_mode="false"
test || __() {
  set -ex;
}

provision_account() {
  local output
  output=$(REDISCLI_AUTH="$REDIS_DEFAULT_PASSWORD" redis-cli $REDIS_CLI_TLS_CMD -p "$SERVICE_PORT" ${KB_ACCOUNT_STATEMENT} 2>&1)
  if [ $? -ne 0 ]; then
    echo "account provision failed: connection error: $output" >&2
    return 1
  fi
  if echo "$output" | grep -qE "(ERR |NOAUTH|WRONGPASS|NOPERM)"; then
    echo "account provision failed: $output" >&2
    return 1
  fi

  output=$(REDISCLI_AUTH="$REDIS_DEFAULT_PASSWORD" redis-cli $REDIS_CLI_TLS_CMD -p "$SERVICE_PORT" acl save 2>&1)
  if [ $? -ne 0 ]; then
    echo "account provision failed: acl save connection error: $output" >&2
    return 1
  fi
  if echo "$output" | grep -qE "(ERR |NOAUTH|WRONGPASS|NOPERM)"; then
    echo "account provision failed: acl save error: $output" >&2
    return 1
  fi
}

${__SOURCED__:+false} : || return 0

provision_account
