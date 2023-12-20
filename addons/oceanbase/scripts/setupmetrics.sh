#!/usr/bin/env bash

source /scripts/sql.sh

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

bin/ob_agentctl config -u \
agent.http.basic.auth.metricAuthEnabled=false,\
monagent.ob.monitor.user=${MONITOR_USER},\
monagent.ob.monitor.password=${MONITOR_PASSWORD},\
monagent.host.ip=${HOSTIP},\
monagent.cluster.id=${CLUSTER_ID},\
monagent.ob.cluster.name=${CLUSTER_NAME},\
monagent.ob.cluster.id=${CLUSTER_ID},\
monagent.ob.zone.name=${ZONE_NAME},\
monagent.pipeline.ob.status=${OB_MONITOR_STATUS},\
monagent.pipeline.node.status=inactive,\
monagent.second.metric.cache.update.interval=5s,\
ocp.agent.monitor.http.port=${SERVICE_PORT} && \
bin/ob_monagent -c conf/monagent.yaml