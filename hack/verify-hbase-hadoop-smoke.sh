#!/usr/bin/env bash
set -euo pipefail

NAMESPACE="demo"
KUBECONFIG_PATH=""
CASES="all"
TIMEOUT_SECONDS=600
DRY_RUN=false
HDFS_STANDALONE_CLUSTER="hdfs-standalone"
HDFS_HA_CLUSTER="hdfs-cluster"
HBASE_STANDALONE_CLUSTER="hbase-standalone"
HBASE_CLUSTER_CLUSTER="hbase-cluster"
SMOKE_ID="smoke$(date +%Y%m%d%H%M%S)"

usage() {
  cat <<'EOF'
Usage: verify-hbase-hadoop-smoke.sh [options]

Options:
  --namespace <namespace>                  Kubernetes namespace. Default: demo
  --kubeconfig <path>                      kubeconfig path for kubectl
  --cases <list>                           Comma-separated cases: hdfs-standalone,hdfs-ha,hbase-standalone,hbase-cluster,all
  --timeout-seconds <seconds>              Wait timeout for cluster and pod readiness. Default: 600
  --hdfs-standalone-cluster <name>         HDFS standalone cluster name. Default: hdfs-standalone
  --hdfs-ha-cluster <name>                 HDFS HA cluster name. Default: hdfs-cluster
  --hbase-standalone-cluster <name>        HBase standalone cluster name. Default: hbase-standalone
  --hbase-cluster <name>                   HBase cluster mode cluster name. Default: hbase-cluster
  --dry-run                                Print commands without executing them
  --help                                   Show this help message
EOF
}

# 功能：打印带时间戳的日志，便于串联 smoke 验证步骤。
# 参数：$1 为日志内容。
# 返回值：始终返回 0。
log() {
  printf '[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$1"
}

# 功能：按 dry-run 开关执行命令；dry-run 时仅打印命令本身。
# 参数：完整命令及参数列表。
# 返回值：真实执行时返回命令退出码；dry-run 时返回 0。
run_cmd() {
  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '+'
    printf ' %q' "$@"
    printf '\n'
    return 0
  fi
  "$@"
}

# 功能：统一执行 kubectl 命令，自动补齐 kubeconfig 与 namespace。
# 参数：kubectl 子命令及参数列表。
# 返回值：同 run_cmd。
run_kubectl() {
  local cmd=(kubectl)
  if [[ -n "${KUBECONFIG_PATH}" ]]; then
    cmd+=(--kubeconfig "${KUBECONFIG_PATH}")
  fi
  cmd+=(-n "${NAMESPACE}")
  cmd+=("$@")
  run_cmd "${cmd[@]}"
}

# 功能：读取 kubectl 命令输出，用于查询集群 phase 与 pod 名称。
# 参数：kubectl 子命令及参数列表。
# 返回值：成功时输出命令结果，失败时返回非 0。
capture_kubectl() {
  local cmd=(kubectl)
  if [[ -n "${KUBECONFIG_PATH}" ]]; then
    cmd+=(--kubeconfig "${KUBECONFIG_PATH}")
  fi
  cmd+=(-n "${NAMESPACE}")
  cmd+=("$@")
  "${cmd[@]}"
}

# 功能：生成 Cluster/Component 对应的 Pod label selector。
# 参数：$1 为 cluster 名称，$2 为 component 名称，可为空。
# 返回值：输出 selector 字符串。
build_selector() {
  local cluster="$1"
  local component="${2:-}"
  local selector="app.kubernetes.io/instance=${cluster}"
  if [[ -n "${component}" ]]; then
    selector+=",apps.kubeblocks.io/component-name=${component}"
  fi
  printf '%s' "${selector}"
}

# 功能：等待 Cluster 进入 Running，作为后续连通性验证的前置条件。
# 参数：$1 为 cluster 名称。
# 返回值：成功返回 0，超时返回非 0。
wait_cluster_running() {
  local cluster="$1"
  local deadline=$((SECONDS + TIMEOUT_SECONDS))
  local phase=""

  if [[ "${DRY_RUN}" == "true" ]]; then
    run_kubectl get cluster "${cluster}" -o jsonpath='{.status.phase}'
    return 0
  fi

  log "等待 Cluster/${cluster} 进入 Running"
  while (( SECONDS < deadline )); do
    phase="$(capture_kubectl get cluster "${cluster}" -o jsonpath='{.status.phase}' 2>/dev/null || true)"
    if [[ "${phase}" == "Running" ]]; then
      return 0
    fi
    sleep 5
  done

  run_kubectl get cluster "${cluster}" -o wide
  echo "cluster ${cluster} did not reach Running within ${TIMEOUT_SECONDS}s" >&2
  return 1
}

# 功能：等待指定 Cluster 下的 Pod Ready。
# 参数：$1 为 cluster 名称，$2 为 component 名称，可为空。
# 返回值：成功返回 0，失败返回非 0。
wait_pods_ready() {
  local cluster="$1"
  local component="${2:-}"
  local selector
  selector="$(build_selector "${cluster}" "${component}")"
  run_kubectl wait --for=condition=Ready pod -l "${selector}" --timeout "${TIMEOUT_SECONDS}s"
}

# 功能：获取指定组件的第一个 Pod 名称，供 exec 连通性验证使用。
# 参数：$1 为 cluster 名称，$2 为 component 名称。
# 返回值：输出 pod 名称；获取失败时返回非 0。
first_pod() {
  local cluster="$1"
  local component="$2"
  local selector
  selector="$(build_selector "${cluster}" "${component}")"

  if [[ "${DRY_RUN}" == "true" ]]; then
    printf '%s-%s-0\n' "${cluster}" "${component}"
    return 0
  fi

  capture_kubectl get pod -l "${selector}" -o jsonpath='{.items[0].metadata.name}'
}

# 功能：在目标 Pod 的指定容器中执行命令。
# 参数：$1 为 pod 名称，$2 为 container 名称，其余参数为待执行命令。
# 返回值：同 run_kubectl。
exec_in_pod() {
  local pod="$1"
  local container="$2"
  shift 2
  run_kubectl exec "${pod}" -c "${container}" -- "$@"
}

# 功能：读取 HDFS HA 的逻辑 nameservice 和 NameNode IDs，并逐个校验服务状态。
# 参数：$1 为 pod 名称。
# 返回值：成功返回 0，失败返回非 0。
verify_hdfs_ha_services() {
  local pod="$1"
  local verify_script=""

  verify_script=$(cat <<'EOF'
set -euo pipefail
# ponytail: NameNode 容器的 PATH 不包含 HADOOP_HOME/bin，直接走绝对路径，避免环境差异导致 smoke 假失败。
ns="$("${HADOOP_HOME}/bin/hdfs" getconf -confKey dfs.nameservices)"
nn_ids="$("${HADOOP_HOME}/bin/hdfs" getconf -confKey "dfs.ha.namenodes.${ns}")"
IFS=',' read -r -a ids <<< "${nn_ids}"
for id in "${ids[@]}"; do
  "${HADOOP_HOME}/bin/hdfs" haadmin -getServiceState "${id}"
done
EOF
)

  exec_in_pod "${pod}" "hdfs-namenode" bash -lc "${verify_script}"
}

# 功能：执行 HDFS smoke，用最小目录创建和 HA 状态查询验证 provision/connectivity。
# 参数：$1 为 cluster 名称，$2 为是否 HA，取值 true/false。
# 返回值：成功返回 0，失败返回非 0。
verify_hdfs() {
  local cluster="$1"
  local is_ha="$2"
  local pod=""
  local smoke_dir="/${SMOKE_ID}-${cluster}"

  wait_cluster_running "${cluster}"
  wait_pods_ready "${cluster}"
  pod="$(first_pod "${cluster}" "namenode")"

  if [[ "${is_ha}" == "true" ]]; then
    verify_hdfs_ha_services "${pod}"
  fi

  exec_in_pod "${pod}" "hdfs-namenode" bash -lc "set -euo pipefail; \"\${HADOOP_HOME}/bin/hdfs\" dfs -mkdir -p '${smoke_dir}'; \"\${HADOOP_HOME}/bin/hdfs\" dfs -test -d '${smoke_dir}'; \"\${HADOOP_HOME}/bin/hdfs\" dfs -ls /"
}

# 功能：执行 HBase Shell smoke，并在 HDFS 模式下额外验证 rootdir 可达。
# 参数：$1 为 cluster 名称，$2 为 component 名称，$3 为 container 名称，$4 为是否校验 HDFS rootdir。
# 返回值：成功返回 0，失败返回非 0。
verify_hbase() {
  local cluster="$1"
  local component="$2"
  local container="$3"
  local verify_hdfs_root="$4"
  local pod=""
  local table="kb_smoke_${cluster//-/_}_${SMOKE_ID}"
  local hbase_shell_script=""

  wait_cluster_running "${cluster}"
  wait_pods_ready "${cluster}"
  pod="$(first_pod "${cluster}" "${component}")"

  hbase_shell_script=$(cat <<EOF
set -euo pipefail
printf '%s\n' \
  "status 'simple'" \
  "create '${table}', 'f'" \
  "put '${table}', 'r1', 'f:c', 'ok'" \
  "scan '${table}', {LIMIT => 1}" \
  "disable '${table}'" \
  "drop '${table}'" \
  | "\${HBASE_HOME}/bin/hbase" shell -n
EOF
)
  exec_in_pod "${pod}" "${container}" bash -lc "${hbase_shell_script}"

  if [[ "${verify_hdfs_root}" == "true" ]]; then
    exec_in_pod "${pod}" "${container}" bash -lc "set -euo pipefail; \"\${HBASE_HOME}/bin/hbase\" org.apache.hadoop.fs.FsShell -test -d \"/\${HBASE_ROOT_DIR}\"; \"\${HBASE_HOME}/bin/hbase\" org.apache.hadoop.fs.FsShell -ls \"/\${HBASE_ROOT_DIR}\""
  fi
}

# 功能：按 case 名称执行对应的 smoke 验证步骤。
# 参数：$1 为 case 名称。
# 返回值：成功返回 0，未知 case 返回非 0。
run_case() {
  local case_name="$1"
  case "${case_name}" in
    hdfs-standalone)
      log "执行 HDFS standalone smoke"
      verify_hdfs "${HDFS_STANDALONE_CLUSTER}" "false"
      ;;
    hdfs-ha)
      log "执行 HDFS HA smoke"
      verify_hdfs "${HDFS_HA_CLUSTER}" "true"
      ;;
    hbase-standalone)
      log "执行 HBase standalone smoke"
      verify_hbase "${HBASE_STANDALONE_CLUSTER}" "hbase-standalone" "hbase-standalone" "false"
      ;;
    hbase-cluster)
      log "执行 HBase + HDFS smoke"
      verify_hbase "${HBASE_CLUSTER_CLUSTER}" "hmaster" "hbase-hmaster" "true"
      ;;
    all)
      run_case "hdfs-standalone"
      run_case "hdfs-ha"
      run_case "hbase-standalone"
      run_case "hbase-cluster"
      ;;
    *)
      echo "unknown case: ${case_name}" >&2
      return 1
      ;;
  esac
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --namespace)
      NAMESPACE="$2"
      shift 2
      ;;
    --kubeconfig)
      KUBECONFIG_PATH="$2"
      shift 2
      ;;
    --cases)
      CASES="$2"
      shift 2
      ;;
    --timeout-seconds)
      TIMEOUT_SECONDS="$2"
      shift 2
      ;;
    --hdfs-standalone-cluster)
      HDFS_STANDALONE_CLUSTER="$2"
      shift 2
      ;;
    --hdfs-ha-cluster)
      HDFS_HA_CLUSTER="$2"
      shift 2
      ;;
    --hbase-standalone-cluster)
      HBASE_STANDALONE_CLUSTER="$2"
      shift 2
      ;;
    --hbase-cluster)
      HBASE_CLUSTER_CLUSTER="$2"
      shift 2
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

IFS=',' read -r -a case_list <<< "${CASES}"
for case_name in "${case_list[@]}"; do
  run_case "${case_name}"
done

log "smoke verification completed"
