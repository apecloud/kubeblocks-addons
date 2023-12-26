#!/usr/bin/env bash

function retry {
  local max_attempts=10
  local attempt=1
  until "$@" || [ $attempt -eq $max_attempts ]; do
    echo "Command '$*' failed. Attempt $attempt of $max_attempts. Retrying in 5 seconds..."
    attempt=$((attempt + 1))
    sleep 5
  done
  if [ $attempt -eq $max_attempts ]; then
    echo "Command '$*' failed after $max_attempts attempts. Exiting..."
    exit 1
  fi
}

ZONE_COUNT=${ZONE_COUNT:-3}
MANAGER_PORT=${MANAGER_PORT:-8089}
SERVICE_PORT=${SERVICE_PORT:-8088}
COMP_RPC_PORT=${COMP_RPC_PORT:-2882}
ORDINAL_OB_PORT=${OB_SERVICE_PORT:-2882}
COMP_MYSQL_PORT=${COMP_MYSQL_PORT:-${ORDINAL_OB_PORT}}
ORDINAL_INDEX=$(echo $KB_POD_NAME | awk -F '-' '{print $(NF)}')
ZONE_NAME="zone$((${ORDINAL_INDEX}%${ZONE_COUNT}))"

INITIAL_DELAY=${INITIAL_DELAY:-5}

## TODO wait ob restarted
echo "Waiting for observer to be ready..."
# import mysql client to metrics
sleep ${INITIAL_DELAY}
retry /kb_tools/obtools --host 127.0.0.1 -u${MONITOR_USER} -P ${COMP_MYSQL_PORT} --allow-native-passwords ping

echo ""
echo "==================================================================================="
echo "update metric config:"
echo "  ob.logcleaner.enabled=false"
echo "  agent.http.basic.auth.metricAuthEnabled=false"
echo "  monagent.log.level=info"
echo "  monagent.log.maxage.days=3"
echo "  monagent.log.maxsize.mb=100"
echo "  monagent.ob.monitor.user=${MONITOR_USER}"
echo "  monagent.ob.sql.port=${COMP_MYSQL_PORT}"
echo "  monagent.ob.rpc.port=${COMP_RPC_PORT}"
echo "  monagent.host.ip=${KB_POD_IP}"
echo "  monagent.cluster.id=${CLUSTER_ID}"
echo "  monagent.ob.cluster.name=${CLUSTER_NAME}"
echo "  monagent.ob.cluster.id=${CLUSTER_ID}"
echo "  monagent.ob.zone.name=${ZONE_NAME}"
echo "  monagent.pipeline.ob.status=${OB_MONITOR_STATUS}"
echo "  monagent.pipeline.node.status=inactive"
echo "  monagent.pipeline.ob.log.status=inactive"
echo "  monagent.pipeline.ob.alertmanager.status=inactive"
echo "  monagent.second.metric.cache.update.interval=5s"
echo "  ocp.agent.manager.http.port=${MANAGER_PORT}"
echo "  ocp.agent.monitor.http.port=${SERVICE_PORT}"
echo "==================================================================================="
echo ""

/home/admin/obagent/bin/ob_agentctl config -u \
ob.logcleaner.enabled=false,\
agent.http.basic.auth.metricAuthEnabled=false,\
monagent.log.level=info,\
monagent.log.maxage.days=3,\
monagent.log.maxsize.mb=100,\
monagent.ob.monitor.user=${MONITOR_USER},\
monagent.ob.monitor.password=${MONITOR_PASSWORD},\
monagent.ob.sql.port=${COMP_MYSQL_PORT},\
monagent.ob.rpc.port=${COMP_RPC_PORT},\
monagent.host.ip=${KB_POD_IP},\
monagent.cluster.id=${CLUSTER_ID},\
monagent.ob.cluster.name=${CLUSTER_NAME},\
monagent.ob.cluster.id=${CLUSTER_ID},\
monagent.ob.zone.name=${ZONE_NAME},\
monagent.pipeline.ob.status=${OB_MONITOR_STATUS},\
monagent.pipeline.node.status=inactive,\
monagent.pipeline.ob.log.status=inactive,\
monagent.pipeline.ob.alertmanager.status=inactive,\
monagent.second.metric.cache.update.interval=5s,\
ocp.agent.manager.http.port=${MANAGER_PORT},\
ocp.agent.monitor.http.port=${SERVICE_PORT} && \
/home/admin/obagent/bin/ob_monagent -c /home/admin/obagent/conf/monagent.yaml