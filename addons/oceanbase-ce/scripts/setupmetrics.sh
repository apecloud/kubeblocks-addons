#!/usr/bin/env bash
source /scripts/utils.sh

function retry {
  until "$@" ; do
    echo "Command failed. Attempt $attempt of $max_attempts. Retrying in 5 seconds..."
    sleep 5
  done
}

ZONE_COUNT=${ZONE_COUNT:-3}
MANAGER_PORT=${MANAGER_PORT:-8089}
SERVICE_PORT=${SERVICE_PORT:-8088}
OB_RPC_PORT=${OB_RPC_PORT:-2882}
OB_SERVICE_PORT=${OB_SERVICE_PORT:-2881}
OB_ROOT_PASSWD=${OB_ROOT_PASSWD:-""}
ORDINAL_INDEX=$(echo $POD_NAME | awk -F '-' '{print $(NF)}')
ZONE_NAME="zone$((${ORDINAL_INDEX}%${ZONE_COUNT}))"
CLUSTER_ID=${OB_CLUSTER_ID:-1}
INITIAL_DELAY=${INITIAL_DELAY:-5}

## TODO wait ob restarted
echo "Waiting for observer to be ready..."
# import mysql client to metrics
sleep ${INITIAL_DELAY}

obcli_cmd="/kb_tools/obtools --host 127.0.0.1 -u${MONITOR_USER} -P ${OB_SERVICE_PORT} --allow-native-passwords ping"
if [ -n "${OB_ROOT_PASSWD}" ]; then
  obcli_cmd=$obcli_cmd" -p ${OB_ROOT_PASSWD}"
fi
retry ${obcli_cmd}

echo ""
echo "==================================================================================="
echo "update metric config:"
echo "  ob.logcleaner.enabled=false"
echo "  agent.http.basic.auth.metricAuthEnabled=false"
echo "  monagent.log.level=info"
echo "  monagent.log.maxage.days=3"
echo "  monagent.log.maxsize.mb=100"
echo "  monagent.ob.monitor.user=${MONITOR_USER}"
echo "  monagent.ob.sql.port=${OB_SERVICE_PORT}"
echo "  monagent.ob.rpc.port=${OB_RPC_PORT}"
echo "  monagent.host.ip=${POD_IP}"
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

if [ -z "${MONITOR_PASSWORD}" ]; then
  echo "MONITOR_PASSWORD is not set, update it with ROOT_PASSWD"
  MONITOR_PASSWORD=$OB_ROOT_PASSWD
fi

/home/admin/obagent/bin/ob_agentctl config -u \
ob.logcleaner.enabled=false,\
agent.http.basic.auth.metricAuthEnabled=false,\
monagent.log.level=info,\
monagent.log.maxage.days=3,\
monagent.log.maxsize.mb=100,\
monagent.ob.monitor.user=${MONITOR_USER},\
monagent.ob.monitor.password=${MONITOR_PASSWORD},\
monagent.ob.sql.port=${OB_SERVICE_PORT},\
monagent.ob.rpc.port=${OB_RPC_PORT},\
monagent.host.ip=${POD_IP},\
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