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
service_port=${INNER_SERVICE_PORT:-6379}
if [ -z $REDIS_DEFAULT_PASSWORD ]; then
  redis-cli -p $service_portCONFIG SET ${paramName} "${paramValue}"
else
  redis-cli -p $service_port -a ${REDIS_DEFAULT_PASSWORD} CONFIG SET ${paramName} "${paramValue}"
fi
