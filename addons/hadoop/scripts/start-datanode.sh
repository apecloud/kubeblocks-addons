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
UNREGISTER_RETRY_PID=""

shutdown() {
  echo "[$(date)] Stopping DataNode..."
  if [[ -n "${UNREGISTER_RETRY_PID}" ]]; then
    kill "${UNREGISTER_RETRY_PID}" >/dev/null 2>&1 || true
  fi
  "${HADOOP_HOME}/bin/hdfs" --daemon stop datanode || true
  exit 0
}

# Function: Retry DataNode unregister in background so transient control-plane failures do not leave the node stuck in decommission state.
# Args: None.
# Returns: 0 when unregister succeeds immediately or the background retry loop is started.
start_unregister_retry_loop() {
  [[ "${HDFS_DECOMMISSION_ENABLED:-true}" == "true" ]] || return 0

  local retry_interval script_path
  retry_interval="${HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS:-5}"
  script_path="$(dirname "$0")/datanode-decommission.sh"

  if "${script_path}" unregister; then
    return 0
  fi

  echo "[$(date)] initial unregister failed, retrying in background every ${retry_interval}s..."
  (
    while true; do
      sleep "${retry_interval}"
      if "${script_path}" unregister; then
        echo "[$(date)] background unregister succeeded"
        exit 0
      fi
      echo "[$(date)] background unregister failed, retrying in ${retry_interval}s..."
    done
  ) &
  UNREGISTER_RETRY_PID=$!
}

trap shutdown SIGTERM SIGINT

start_unregister_retry_loop
echo "[$(date)] Starting DataNode..."
"${HADOOP_HOME}/bin/hdfs" datanode 2>&1 | tee -a "$LOG_FILE" &
DN_PID=$!
wait $DN_PID
if [[ -n "${UNREGISTER_RETRY_PID}" ]]; then
  kill "${UNREGISTER_RETRY_PID}" >/dev/null 2>&1 || true
fi
