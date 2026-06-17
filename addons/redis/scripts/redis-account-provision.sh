#!/bin/bash

ut_mode="false"
test || __() {
  set -ex;
}

provision_account() {
  local redis_base_cmd="redis-cli $REDIS_CLI_TLS_CMD -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD"

  local output
  output=$($redis_base_cmd ${KB_ACCOUNT_STATEMENT} 2>&1)
  if [ $? -ne 0 ]; then
    echo "account provision failed: connection error: $output" >&2
    return 1
  fi
  if echo "$output" | grep -qE "^(ERR|NOAUTH|WRONGPASS|NOPERM)"; then
    echo "account provision failed: $output" >&2
    return 1
  fi

  if ! $redis_base_cmd acl save; then
    echo "account provision failed: acl save error" >&2
    return 1
  fi
}

${__SOURCED__:+false} : || return 0

provision_account
