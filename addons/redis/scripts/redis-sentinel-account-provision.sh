#!/bin/bash

ut_mode="false"
test || __() {
  set -ex;
}

provision_sentinel_account() {
  local redis_base_cmd="redis-cli $REDIS_CLI_TLS_CMD -p $SENTINEL_SERVICE_PORT -a $SENTINEL_PASSWORD"

  output=$($redis_base_cmd ${KB_ACCOUNT_STATEMENT} 2>&1)
  if [ $? -ne 0 ]; then
    echo "sentinel account provision failed: connection error: $output" >&2
    return 1
  fi
  if echo "$output" | grep -q "^ERR"; then
    echo "sentinel account provision failed: $output" >&2
    return 1
  fi

  $redis_base_cmd acl save
}

${__SOURCED__:+false} : || return 0

provision_sentinel_account
