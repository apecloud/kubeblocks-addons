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
LOG_FILE="${HADOOP_LOG_DIR}/hadoop-${USER}-journalnode-$(hostname).log"

shutdown() {
  echo "[$(date)] Stopping JournalNode..."
  "${HADOOP_HOME}/bin/hdfs" --daemon stop journalnode || true
  exit 0
}
trap shutdown SIGTERM SIGINT

echo "[$(date)] Starting JournalNode..."
"${HADOOP_HOME}/bin/hdfs" journalnode 2>&1 | tee -a "$LOG_FILE" &
JN_PID=$!
wait $JN_PID
