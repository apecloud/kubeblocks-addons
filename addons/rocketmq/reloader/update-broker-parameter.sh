#!/bin/bash
set -e

paramName="${1:?missing param name}"
paramValue="${2:?missing value}"

export NAMESRV_ADDR=${ALL_NAMESRV_FQDN//,/:${NAMESRV_PORT};}:${NAMESRV_PORT}
export PATH="$PATH:/opt/java/openjdk/bin"
/home/rocketmq/rocketmq-"${ROCKETMQ_VERSION}"/bin/mqadmin updateBrokerConfig -b "${MY_POD_IP}:${BROKER_PORT}" -k "${paramName}" -v "${paramValue}"