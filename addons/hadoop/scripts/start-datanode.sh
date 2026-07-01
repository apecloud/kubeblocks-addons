#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
: "${HADOOP_LOG_DIR:=/var/log/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR HADOOP_LOG_DIR
export HADOOP_PID_DIR=/var/run/hadoop
mkdir -p "${HADOOP_LOG_DIR}" "${HADOOP_PID_DIR}"

USER=$(whoami)
LOG_FILE="${HADOOP_LOG_DIR}/hadoop-${USER}-datanode-$(hostname).log"

shutdown() {
  echo "[$(date)] Stopping DataNode..."
  "${HADOOP_HOME}/bin/hdfs" --daemon stop datanode || true
  exit 0
}
trap shutdown SIGTERM SIGINT

echo "[$(date)] Starting DataNode..."
"${HADOOP_HOME}/bin/hdfs" datanode 2>&1 | tee -a "$LOG_FILE" &
DN_PID=$!
wait $DN_PID
