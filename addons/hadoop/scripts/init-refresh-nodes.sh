#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

echo "[$(date)] Refreshing DataNode include/exclude lists on NameNode..."
"${HADOOP_HOME}/bin/hdfs" dfsadmin -refreshNodes || true
echo "[$(date)] refreshNodes completed"
