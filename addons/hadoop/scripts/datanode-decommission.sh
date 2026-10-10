#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
: "${NAMESPACE:=default}"
: "${HDFS_DECOMMISSION_ENABLED:=true}"
: "${HDFS_DECOMMISSION_TIMEOUT_SECONDS:=300}"
: "${HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS:=5}"
: "${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME:=hdfs-decommission-state}"
export HADOOP_HOME HADOOP_CONF_DIR

CURRENT_HOST="${KB_LEAVE_MEMBER_POD_FQDN:-${POD_FQDN:-$(hostname -f 2>/dev/null || hostname)}}"
KUBE_TOKEN_FILE="/var/run/secrets/kubernetes.io/serviceaccount/token"
KUBE_CA_FILE="/var/run/secrets/kubernetes.io/serviceaccount/ca.crt"
KUBE_API_SERVER="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS:-443}"

# 功能：打印 DataNode decommission 相关日志，便于排查状态同步和等待过程。
# 参数：$1 为日志内容。
# 返回值：始终返回 0。
log() {
    echo "[$(date)] $1"
}

# 功能：对 ConfigMap key/value 中的特殊字符做 JSON 转义，确保 merge-patch 载荷合法。
# 参数：$1 为待转义字符串。
# 返回值：输出转义后的字符串。
json_escape() {
    local value="$1"
    value="${value//\\/\\\\}"
    value="${value//\"/\\\"}"
    value="${value//$'\n'/\\n}"
    printf '%s' "${value}"
}

# 功能：向 Kubernetes API 发送 merge-patch，请求更新中心 decommission ConfigMap。
# 参数：$1 为 JSON patch 载荷。
# 返回值：成功返回 0，失败返回非 0。
patch_state_configmap() {
    local patch_body="$1"
    curl --silent --show-error --fail \
        --cacert "${KUBE_CA_FILE}" \
        -H "Authorization: Bearer $(<"${KUBE_TOKEN_FILE}")" \
        -H "Content-Type: application/merge-patch+json" \
        -X PATCH \
        "${KUBE_API_SERVER}/api/v1/namespaces/${NAMESPACE}/configmaps/${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME}" \
        --data "${patch_body}" >/dev/null
}

# 功能：在中心 decommission ConfigMap 不存在时按最小结构创建它，确保 register/unregister 有状态源可写。
# 参数：无。
# 返回值：创建成功、已存在或确认存在时返回 0，失败返回非 0。
ensure_state_configmap() {
    local create_body http_code
    if curl --silent --show-error --fail \
        --cacert "${KUBE_CA_FILE}" \
        -H "Authorization: Bearer $(<"${KUBE_TOKEN_FILE}")" \
        "${KUBE_API_SERVER}/api/v1/namespaces/${NAMESPACE}/configmaps/${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME}" >/dev/null; then
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

# 功能：按动作同步当前 DataNode 的中心化 exclude 状态，支持注册和注销两种路径。
# 参数：$1 为动作，支持 register 或 unregister。
# 返回值：成功返回 0，失败返回非 0。
sync_current_host() {
    local action="$1"
    local host_key host_value patch_body
    local escaped_key escaped_value

    [[ "${HDFS_DECOMMISSION_ENABLED}" == "true" ]] || return 0
    [[ -f "${KUBE_TOKEN_FILE}" && -f "${KUBE_CA_FILE}" ]] || {
        log "service account token is unavailable, cannot sync decommission state"
        return 1
    }
    ensure_state_configmap || {
        log "failed to ensure decommission state configmap ${HDFS_DECOMMISSION_STATE_CONFIGMAP_NAME}"
        return 1
    }

    host_key="$(json_escape "${CURRENT_HOST}")"
    host_value="$(json_escape "${CURRENT_HOST}")"

    if [[ "${action}" == "register" ]]; then
        patch_body="{\"data\":{\"${host_key}\":\"${host_value}\"}}"
    else
        patch_body="{\"data\":{\"${host_key}\":null}}"
    fi

    for _ in $(seq 1 6); do
        if patch_state_configmap "${patch_body}"; then
            return 0
        fi
        sleep "${HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS}"
    done

    return 1
}

# 功能：判断目标主机与候选标识是否代表同一个 DataNode，兼容 FQDN、短主机名和 Name 字段里的别名。
# 参数：$1 为目标主机标识；$2 为待匹配的候选标识。
# 返回值：匹配返回 0，不匹配返回 1。
host_matches_candidate() {
    local host="$1"
    local candidate="$2"
    local host_short candidate_short

    candidate="${candidate#"${candidate%%[![:space:]]*}"}"
    candidate="${candidate%"${candidate##*[![:space:]]}"}"
    [[ -n "${candidate}" ]] || return 1

    host_short="${host%%.*}"
    candidate_short="${candidate%%.*}"

    [[ "${candidate}" == "${host}" || "${candidate}" == "${host_short}" || "${candidate_short}" == "${host}" || "${candidate_short}" == "${host_short}" ]]
}

# 功能：从 dfsadmin -report 输出中提取目标 DataNode 的 decommission 状态，兼容 Name 别名和 Hostname 字段。
# 参数：$1 为 report 文件路径；$2 为目标主机标识。
# 返回值：找到状态时输出状态文本并返回 0；未找到时输出空串并返回 0。
extract_decommission_status_from_report() {
    local report_file="$1"
    local host="$2"
    local line current candidate status
    local matched="false"

    while IFS= read -r line; do
        if [[ "${line}" == Name:\ * ]]; then
            matched="false"
            current="${line#Name: }"
            current="${current%% *}"
            current="${current%:*}"
            if host_matches_candidate "${host}" "${current}"; then
                matched="true"
                continue
            fi
            if [[ "${line}" == *"("*")"* ]]; then
                candidate="${line#*\(}"
                candidate="${candidate%%\)*}"
                if host_matches_candidate "${host}" "${candidate}"; then
                    matched="true"
                fi
            fi
            continue
        fi

        if [[ "${line}" == Hostname:\ * ]]; then
            candidate="${line#Hostname: }"
            if host_matches_candidate "${host}" "${candidate}"; then
                matched="true"
            fi
            continue
        fi

        if [[ "${matched}" == "true" && "${line}" =~ Decommission[[:space:]]+Status[[:space:]]*:[[:space:]]*(.+)$ ]]; then
            status="${BASH_REMATCH[1]}"
            printf '%s\n' "${status}"
            return 0
        fi
    done <"${report_file}"
}

# 功能：等待 NameNode 完成当前 DataNode 的 decommission，直到状态变为 Decommissioned。
# 参数：无，依赖 HDFS_DECOMMISSION_TIMEOUT_SECONDS 和 HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS。
# 返回值：成功返回 0，超时或状态异常返回非 0。
wait_for_decommission() {
    local deadline report_file status
    report_file="$(mktemp)"
    trap 'rm -f "${report_file}"' RETURN
    deadline=$((SECONDS + HDFS_DECOMMISSION_TIMEOUT_SECONDS))

    while (( SECONDS < deadline )); do
        if "${HADOOP_HOME}/bin/hdfs" dfsadmin -report >"${report_file}" 2>/dev/null; then
            status="$(extract_decommission_status_from_report "${report_file}" "${CURRENT_HOST}")"
            if [[ "${status}" == "Decommissioned" ]]; then
                log "DataNode ${CURRENT_HOST} successfully decommissioned"
                return 0
            fi
        fi
        sleep "${HDFS_DECOMMISSION_POLL_INTERVAL_SECONDS}"
    done

    log "Timed out waiting for DataNode ${CURRENT_HOST} to reach Decommissioned"
    return 1
}

case "${1:-register}" in
    register)
        [[ "${HDFS_DECOMMISSION_ENABLED}" == "true" ]] || {
            log "DataNode decommission is disabled, skipping register flow"
            exit 0
        }
        log "Starting DataNode decommission for ${CURRENT_HOST}"
        sync_current_host "register"
        wait_for_decommission
        ;;
    unregister)
        [[ "${HDFS_DECOMMISSION_ENABLED}" == "true" ]] || {
            log "DataNode decommission is disabled, skipping unregister flow"
            exit 0
        }
        log "Removing ${CURRENT_HOST} from decommission state"
        sync_current_host "unregister"
        ;;
    *)
        echo "unsupported action: ${1}" >&2
        exit 1
        ;;
esac
