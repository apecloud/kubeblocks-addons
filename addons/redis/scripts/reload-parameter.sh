#!/bin/bash

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -e;
}

service_port=${SERVICE_PORT:-6379}

reload_redis_parameter() {
  local paramName=""
  local paramValue=""
  # shellcheck disable=SC2086
  for val in $(echo "${1}" | tr ' ' '\n'); do
    if [ -z "${paramName}" ]; then
      paramName="${val}"
    elif [ -z "${paramValue}" ]; then
      paramValue="${val}"
    else
      paramValue="${paramValue} ${val}"
    fi
  done

  if [ -z "${paramValue}" ]; then
    paramValue="${@:2}"
  else
    paramValue="${paramValue} ${@:2}"
  fi

  if [ "$paramValue" = "\"\"" ]; then
    paramValue=""
  fi

  # shellcheck disable=SC2086
  if [ -z $REDIS_DEFAULT_PASSWORD ]; then
    # shellcheck disable=SC2086
    redis-cli $REDIS_CLI_TLS_CMD -p $service_port CONFIG SET ${paramName} "${paramValue}"
  else
    # shellcheck disable=SC2086
    redis-cli $REDIS_CLI_TLS_CMD -p $service_port -a ${REDIS_DEFAULT_PASSWORD} CONFIG SET ${paramName} "${paramValue}"
  fi
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

reload_redis_parameter "$@"
