#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

echo "Formatting ZKFC (creating HA znode in ZooKeeper)..."
echo "N" | "${HADOOP_HOME}/bin/hdfs" zkfc -formatZK || true
echo "ZKFC format completed"
