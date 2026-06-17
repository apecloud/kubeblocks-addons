#!/bin/sh

ut_mode="false"
test || __() {
  set -ex;
}

provision_sentinel_account() {
  local output
  output=$(REDISCLI_AUTH="$SENTINEL_PASSWORD" redis-cli $REDIS_CLI_TLS_CMD -p "$SENTINEL_SERVICE_PORT" ${KB_ACCOUNT_STATEMENT} 2>&1)
  if [ $? -ne 0 ]; then
    echo "sentinel account provision failed: connection error: $output" >&2
    return 1
  fi
  if echo "$output" | grep -qE "(ERR |NOAUTH|WRONGPASS|NOPERM)"; then
    echo "sentinel account provision failed: $output" >&2
    return 1
  fi

  output=$(REDISCLI_AUTH="$SENTINEL_PASSWORD" redis-cli $REDIS_CLI_TLS_CMD -p "$SENTINEL_SERVICE_PORT" acl save 2>&1)
  if [ $? -ne 0 ]; then
    echo "sentinel account provision failed: acl save connection error: $output" >&2
    return 1
  fi
  if echo "$output" | grep -qE "(ERR |NOAUTH|WRONGPASS|NOPERM)"; then
    echo "sentinel account provision failed: acl save error: $output" >&2
    return 1
  fi
}

${__SOURCED__:+false} : || return 0

provision_sentinel_account
