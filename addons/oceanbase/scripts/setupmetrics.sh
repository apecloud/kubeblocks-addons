#!/usr/bin/env bash

source /scripts/sql.sh

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

INITIAL_DELAY=${INITIAL_DELAY:-5}
ZONE_COUNT=${ZONE_COUNT:-3}
HOSTIP=$(hostname -i)
#REP_USER=${REP_USER:-rep_user}
#REP_PASSWD=${REP_PASSWD:-rep_user}

ORDINAL_INDEX=$(echo $KB_POD_NAME | awk -F '-' '{print $(NF)}')
echo "ORDINAL_INDEX: $ORDINAL_INDEX"
echo "ZONE_NAME: $ZONE_NAME"

ZONE_NAME="zone$((${ORDINAL_INDEX}%${ZONE_COUNT}))"
#MONITOR_USER=${REP_USER}
#MONITOR_PASSWORD=${REP_PASSWD}

## TODO wait ob restarted
echo "Waiting for observer to be ready..."
# import mysql client to metrics
sleep ${INITIAL_DELAY}
retry /kb_tools/obtools --host 127.0.0.1 -u${MONITOR_USER} -P ${OB_SERVICE_PORT} --allow-native-passwords ping

/home/admin/obagent/bin/ob_agentctl config -u \
ob.logcleaner.enabled=false,\
agent.http.basic.auth.metricAuthEnabled=false,\
monagent.log.level=info,\
monagent.log.maxage.days=3,\
monagent.log.maxsize.mb=100,\
monagent.ob.monitor.user=${MONITOR_USER},\
monagent.ob.monitor.password=${MONITOR_PASSWORD},\
monagent.host.ip=${HOSTIP},\
monagent.cluster.id=${CLUSTER_ID},\
monagent.ob.cluster.name=${CLUSTER_NAME},\
monagent.ob.cluster.id=${CLUSTER_ID},\
monagent.ob.zone.name=${ZONE_NAME},\
monagent.pipeline.ob.status=${OB_MONITOR_STATUS},\
monagent.pipeline.node.status=inactive,\
monagent.pipeline.ob.log.status=inactive,\
monagent.pipeline.ob.alertmanager.status=inactive,\
monagent.second.metric.cache.update.interval=5s,\
ocp.agent.monitor.http.port=${SERVICE_PORT} && \
/home/admin/obagent/bin/ob_monagent -c /home/admin/obagent/conf/monagent.yaml