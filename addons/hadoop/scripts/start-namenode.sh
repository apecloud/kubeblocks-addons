#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
: "${HADOOP_LOG_DIR:=/var/log/hadoop}"
: "${HADOOP_PID_DIR:=/tmp/hadoop}"
: "${HDFS_HA_NAMENODE_IDS:=nn0,nn1}"
: "${HDFS_HA_STANDBY_ORDINAL:=1}"
: "${LIFECYCLE_DIR:=/lifecycle}"

export HADOOP_HOME HADOOP_CONF_DIR HADOOP_LOG_DIR HADOOP_PID_DIR
mkdir -p "${HADOOP_LOG_DIR}" "${HADOOP_PID_DIR}" "${LIFECYCLE_DIR}"

USER=$(whoami)
LOG_FILE="${HADOOP_LOG_DIR}/hadoop-${USER}-namenode-$(hostname).log"

# 功能：仅在 standby ordinal 上执行 bootstrapStandby，避免与 OrderedReady 启动顺序冲突。
# 参数：无，依赖 POD_NAME、HADOOP_HOME、HADOOP_CONF_DIR 等环境变量。
# 返回值：成功返回 0，失败返回非 0。
bootstrap_standby_if_needed() {
  local pod_name host_name ordinal nameservices nn_ids peer_id peer_rpc peer_host
  local name_dirs nn_dir nn_current_dir

  pod_name="${POD_NAME:-$(hostname)}"
  host_name="$(hostname)"
  ordinal="${pod_name##*-}"
  [[ "$ordinal" == "$pod_name" ]] && ordinal="${host_name##*-}"

  # ponytail: 当前 addon 的 HA 语义固定为双 NameNode，standby ordinal 集中在这里；扩展更多 NN 时再引入显式 nnId 映射。
  [[ "$ordinal" == "${HDFS_HA_STANDBY_ORDINAL}" ]] || return 0

  nameservices=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.nameservices 2>/dev/null || echo "")
  [[ -n "$nameservices" ]] || return 0

  nn_ids=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey "dfs.ha.namenodes.${nameservices}" 2>/dev/null || echo "")
  [[ "$nn_ids" == *","* ]] || return 0

  name_dirs=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.namenode.name.dir 2>/dev/null || echo "")
  [[ -n "$name_dirs" ]] || return 0
  nn_dir="${name_dirs%%,*}"
  nn_dir="${nn_dir#file://}"
  nn_current_dir="${nn_dir}/current"

  if [[ -d "$nn_current_dir" ]] && find "$nn_current_dir" -maxdepth 1 -type f -name 'fsimage_*' ! -name '*.md5' 2>/dev/null | grep -q .; then
    echo "[$(date)] Valid fsimage found at ${nn_current_dir}, skipping bootstrapStandby"
    return 0
  fi

  peer_id=""
  for nn_id in $(echo "${HDFS_HA_NAMENODE_IDS}" | tr ',' '\n'); do
    if [[ "$nn_id" != "nn${ordinal}" ]]; then
      peer_id="$nn_id"
      break
    fi
  done
  [[ -n "$peer_id" ]] || peer_id="nn0"
  peer_rpc=$("${HADOOP_HOME}/bin/hdfs" getconf -confKey "dfs.namenode.rpc-address.${nameservices}.${peer_id}" 2>/dev/null || echo "")
  peer_host="${peer_rpc%:*}"
  if [[ -z "$peer_host" || "$peer_host" == "$peer_rpc" ]]; then
    echo "[$(date)] Cannot determine active peer host for ${peer_id}, skipping bootstrapStandby"
    return 1
  fi

  for attempt in $(seq 1 30); do
    if getent hosts "$peer_host" >/dev/null 2>&1; then
      break
    fi
    if [[ "$attempt" -eq 30 ]]; then
      echo "[$(date)] Peer ${peer_host} is still unresolved after 60s" >&2
      return 1
    fi
    sleep 2
  done

  echo "[$(date)] No valid fsimage, running bootstrapStandby with retries..."
  for attempt in $(seq 1 30); do
    if "${HADOOP_HOME}/bin/hdfs" namenode -bootstrapStandby -nonInteractive; then
      echo "[$(date)] bootstrapStandby succeeded on attempt ${attempt}"
      return 0
    fi
    echo "[$(date)] bootstrapStandby failed on attempt ${attempt}, retrying in 10s..."
    sleep 10
  done

  echo "[$(date)] bootstrapStandby failed after 30 attempts" >&2
  return 1
}

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

bootstrap_standby_if_needed

echo "[$(date)] Starting NameNode..."
"${HADOOP_HOME}/bin/hdfs" namenode 2>&1 | tee -a "$LOG_FILE" &
NN_PID=$!
wait $NN_PID
