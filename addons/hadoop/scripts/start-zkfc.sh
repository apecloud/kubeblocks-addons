#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
: "${HADOOP_LOG_DIR:=/var/log/hadoop}"
: "${LIFECYCLE_DIR:=/lifecycle}"

export HADOOP_HOME HADOOP_CONF_DIR HADOOP_LOG_DIR
export HADOOP_PID_DIR=/var/run/hadoop
mkdir -p "${HADOOP_LOG_DIR}" "${HADOOP_PID_DIR}" "${LIFECYCLE_DIR}"

USER=$(whoami)
LOG_FILE="${HADOOP_LOG_DIR}/hadoop-${USER}-zkfc-$(hostname).log"

shutdown() {
  echo "[$(date)] Received SIGTERM, waiting for NameNode to terminate..."
  while true; do
    if [[ -f "${LIFECYCLE_DIR}/nn-terminated" ]]; then
      echo "[$(date)] NameNode terminated signal received, stopping ZKFC"
      sleep 10
      "${HADOOP_HOME}/bin/hdfs" --daemon stop zkfc || true
      exit 0
    fi
    sleep 2
  done
}

trap shutdown SIGTERM SIGINT

echo "[$(date)] Starting ZKFC..."
"${HADOOP_HOME}/bin/hdfs" zkfc 2>&1 | tee -a "$LOG_FILE" &
ZKFC_PID=$!
wait $ZKFC_PID
