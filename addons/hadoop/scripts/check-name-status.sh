#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

_NN_HTTP_PORT="${HDFS_NAMENODE_HTTP_PORT:-9870}"

CLUSTER_ID_RESP=$(curl -s --connect-timeout 5 --max-time 10 "http://localhost:${_NN_HTTP_PORT}/jmx?qry=Hadoop:service=NameNode,name=NameNodeInfo" 2>/dev/null || echo "")
if echo "${CLUSTER_ID_RESP}" | grep -q '"ClusterId"'; then
    NN_STATUS=$(curl -s --connect-timeout 5 --max-time 10 "http://localhost:${_NN_HTTP_PORT}/jmx?qry=Hadoop:service=NameNode,name=NameNodeStatus" 2>/dev/null || echo "")
    STATE=$(echo "${NN_STATUS}" | grep -o '"State"[[:space:]]*:[[:space:]]*"[^"]*"' | head -1 | sed 's/.*"State"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
    if [[ -z "$STATE" ]]; then
        echo "NameNode is up but state could not be determined, considering alive"
        exit 0
    fi
    if [[ "$STATE" == "active" || "$STATE" == "standby" ]]; then
        echo "NameNode is ${STATE}"
        exit 0
    fi
    echo "NameNode is in unexpected state: ${STATE}"
    exit 1
fi

echo "NameNode JMX not ready yet"
exit 1
