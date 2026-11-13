#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${NAMESPACE:=default}"
: "${HDFS_DECOMMISSION_ENABLED:=true}"
: "${HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS:=5}"
: "${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME:=hdfs-decommission-state}"
: "${HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE:=${HADOOP_CONF_DIR}/dfs.exclude.dynamic}"
: "${HDFS_DECOMMISSION_REFRESH_PENDING_FILE:=/tmp/hdfs-decommission-refresh.pending}"
: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

KUBE_TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
KUBE_CA_FILE="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
KUBE_API_SERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS:-443}"

# 功能：打印 NameNode 侧 decommission 状态同步日志。
# 参数：$1 为日志内容。
# 返回值：始终返回 0。
log() {
    echo "[$(date)] $1"
}

# 功能：从 Kubernetes API 获取中心 ConfigMap 的 JSON 内容。
# 参数：无。
# 返回值：成功时输出 JSON，失败返回非 0。
fetch_state_configmap() {
    curl --silent --show-error --fail \
        --cacert "${KUBE_CA_FILE}" \
        -H "Authorization: Bearer $(<"${KUBE_TOKEN_FILE}")" \
        "${KUBE_API_SERVER}/api/v1/namespaces/${NAMESPACE}/configmaps/${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME}"
}

# 功能：在 watcher 首次同步前确保中心 decommission ConfigMap 已存在，避免 addon-only 路径因缺资源直接失败。
# 参数：无。
# 返回值：创建成功、已存在或确认存在时返回 0，失败返回非 0。
ensure_state_configmap() {
    local create_body http_code
    if fetch_state_configmap >/dev/null; then
        return 0
    fi

    create_body="{\"apiVersion\":\"v1\",\"kind\":\"ConfigMap\",\"metadata\":{\"name\":\"${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME}\"},\"data\":{}}"
    http_code="$(
        curl --silent --show-error \
            --output /dev/null \
            --write-out '%{http_code}' \
            --cacert "${KUBE_CA_FILE}" \
            -H "Authorization: Bearer $(<"${KUBE_TOKEN_FILE}")" \
            -H "Content-Type: application/json" \
            -X POST \
            "${KUBE_API_SERVER}/api/v1/namespaces/${NAMESPACE}/configmaps" \
            --data "${create_body}"
    )"
    [[ "${http_code}" == "201" || "${http_code}" == "409" ]]
}

# 功能：从 ConfigMap JSON 中抽取所有被标记为待下线的主机名列表。
# 参数：$1 为 ConfigMap JSON 字符串。
# 返回值：输出按行排列的 FQDN 列表；若为空则输出空字符串。
extract_exclude_hosts() {
    local payload="$1"
    local data_section
    data_section="$(printf '%s' "${payload}" | tr -d '\n' | sed -n 's/.*"data":{\([^}]*\)}.*/\1/p')"
    if [[ -z "${data_section}" ]]; then
        return 0
    fi

    printf '%s' "${data_section}" \
        | grep -o '"[^"]*":"[^"]*"' \
        | sed 's/^"[^"]*":"//; s/"$//' \
        | sed 's/\\"/"/g; s/\\\\/\\/g' \
        | sort -u
}

# 功能：将最新 exclude 主机列表写入本地动态文件，并在内容变更时刷新 NameNode 节点视图。
# 参数：无，依赖中心 ConfigMap 和本地动态文件路径。
# 返回值：成功返回 0，失败返回非 0。
refresh_once() {
    local payload tmp_file
    tmp_file="$(mktemp)"
    trap 'rm -f "${tmp_file}"' RETURN

    ensure_state_configmap
    payload="$(fetch_state_configmap)"
    mkdir -p "$(dirname "${HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE}")"
    extract_exclude_hosts "${payload}" > "${tmp_file}"
    touch "${HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE}"

    if ! cmp -s "${tmp_file}" "${HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE}"; then
        mv "${tmp_file}" "${HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE}"
        touch "${HDFS_DECOMMISSION_REFRESH_PENDING_FILE}"
    fi

    if [[ -f "${HDFS_DECOMMISSION_REFRESH_PENDING_FILE}" ]]; then
        log "Exclude state changed, refreshing NameNode nodes"
        if "${HADOOP_HOME}/bin/hdfs" dfsadmin -refreshNodes; then
            rm -f "${HDFS_DECOMMISSION_REFRESH_PENDING_FILE}"
        else
            return 1
        fi
    fi
}

[[ "${HDFS_DECOMMISSION_ENABLED}" == "true" ]] || exit 0
[[ -f "${KUBE_TOKEN_FILE}" && -f "${KUBE_CA_FILE}" ]] || {
    log "service account token is unavailable, watcher exits"
    exit 1
}

touch "${HDFS_DECOMMISSION_DYNAMIC_EXCLUDE_FILE}"
while true; do
    refresh_once || true
    sleep "${HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS}"
done
