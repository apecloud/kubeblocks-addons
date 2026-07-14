#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
: "${HADOOP_LOG_DIR:=/var/log/hadoop}"
: "${HADOOP_PID_DIR:=/tmp/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR HADOOP_LOG_DIR HADOOP_PID_DIR
mkdir -p "${HADOOP_LOG_DIR}" "${HADOOP_PID_DIR}"

USER=$(whoami)
LOG_FILE="${HADOOP_LOG_DIR}/hadoop-${USER}-datanode-$(hostname).log"

shutdown() {
  echo "[$(date)] Stopping DataNode..."
  "${HADOOP_HOME}/bin/hdfs" --daemon stop datanode || true
  exit 0
}
trap shutdown SIGTERM SIGINT

if [[ "${HDFS_DECOMMISSION_ENABLED:-true}" == "true" ]]; then
  # ponytail: 启动前清理残留 decommission 状态属于幂等善后，不该因为控制面瞬时抖动阻塞 DataNode 拉起；若后续需要强一致，可改为带退避的预检查。
  "$(dirname "$0")/datanode-decommission.sh" unregister || true
fi

echo "[$(date)] Starting DataNode..."
"${HADOOP_HOME}/bin/hdfs" datanode 2>&1 | tee -a "$LOG_FILE" &
DN_PID=$!
wait $DN_PID
