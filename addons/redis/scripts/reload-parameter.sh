#!/bin/bash
set -e
paramName=""
paramValue=""
for val in $(echo "${1}" | tr ' ' '\n'); do
  if [ -z "${paramName}" ]; then
    paramName="${val}"
  elif [ -z "${paramValue}" ]; then
    paramValue="${val}"
  else
    paramValue="${paramValue} ${val}"
  fi
done

if  [ -z "${paramValue}" ]; then
  paramValue="${@:2}"
else
  paramValue="${paramValue} ${@:2}"
fi

if [ "$paramValue" = "\"\"" ]; then
  paramValue=""
fi
service_port=${SERVICE_PORT:-6379}

if [ -z $REDIS_DEFAULT_PASSWORD ]; then
  redis-cli -p $service_port $REDIS_CLI_TLS_CMD CONFIG SET ${paramName} "${paramValue}"
else
  redis-cli -p $service_port -a ${REDIS_DEFAULT_PASSWORD} $REDIS_CLI_TLS_CMD CONFIG SET ${paramName} "${paramValue}"
fi
