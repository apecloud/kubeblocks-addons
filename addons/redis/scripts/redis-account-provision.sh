#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -e;
}

redis_account_provision() {
  # shellcheck disable=SC2086
  local redis_base_cmd="redis-cli $REDIS_CLI_TLS_CMD -p $SERVICE_PORT -a $REDIS_DEFAULT_PASSWORD"
  # shellcheck disable=SC2086
  $redis_base_cmd ${KB_ACCOUNT_STATEMENT}
  # shellcheck disable=SC2086
  $redis_base_cmd acl save
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

redis_account_provision
