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
LOG_FILE="${HADOOP_LOG_DIR}/hadoop-${USER}-namenode-$(hostname).log"

shutdown() {
  echo "[$(date)] Received SIGTERM, stopping NameNode gracefully..."
  local is_active=0
  if "${HADOOP_HOME}/bin/hdfs" haadmin -getAllServiceState 2>/dev/null | grep -q "$(hostname -f).*active"; then
    is_active=1
  fi

  if [[ $is_active -eq 1 ]]; then
    local nameservices standby_service=""
    nameservices=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.nameservices 2>/dev/null || echo "")
    if [[ -n "$nameservices" ]]; then
      local nns
      nns=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey "dfs.ha.namenodes.${nameservices}" 2>/dev/null || echo "")
      for nn_id in $(echo "$nns" | tr ',' '\n'); do
        local state
        state=$("${HADOOP_HOME}/bin/hdfs" haadmin -getServiceState "$nn_id" 2>/dev/null || echo "")
        if [[ "$state" == "standby" ]]; then
          standby_service="$nn_id"
          break
        fi
      done

      local my_service=""
      for nn_id in $(echo "$nns" | tr ',' '\n'); do
        local rpc_addr
        rpc_addr=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey "dfs.namenode.rpc-address.${nameservices}.${nn_id}" 2>/dev/null || echo "")
        local rpc_host="${rpc_addr%:*}"
        if [[ "$rpc_host" == "$(hostname -f)" ]] || [[ "$rpc_host" == "$(hostname)" ]]; then
          my_service="$nn_id"
          break
        fi
      done

      if [[ -n "$my_service" && -n "$standby_service" && "$my_service" != "$standby_service" ]]; then
        echo "[$(date)] Active NN ${my_service}, failing over to standby ${standby_service}"
        "${HADOOP_HOME}/bin/hdfs" haadmin -failover "$my_service" "$standby_service" || true
      else
        echo "[$(date)] Cannot determine my_service/standby_service (my=${my_service}, standby=${standby_service}), skipping explicit failover"
      fi
    fi
    echo "[$(date)] Waiting 60s for failover to complete..."
    sleep 60
  else
    echo "[$(date)] NameNode is not active, no failover needed"
  fi

  touch "${LIFECYCLE_DIR}/nn-terminated"
  echo "[$(date)] Stopping NameNode daemon"
  "${HADOOP_HOME}/bin/hdfs" --daemon stop namenode || true
  exit 0
}

EXCLUDE_PATH=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.hosts.exclude 2>/dev/null || echo "")
if [[ -n "$EXCLUDE_PATH" ]]; then
  touch "$EXCLUDE_PATH" || true
fi

trap shutdown SIGTERM SIGINT

echo "[$(date)] Starting NameNode..."
"${HADOOP_HOME}/bin/hdfs" namenode 2>&1 | tee -a "$LOG_FILE" &
NN_PID=$!
wait $NN_PID
