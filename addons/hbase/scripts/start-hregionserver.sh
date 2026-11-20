#!/bin/bash
set -e

source ${HBASE_CONF_DIR}/hbase-env.sh 2>/dev/null || true
mkdir -p ${HBASE_LOG_DIR} ${HBASE_PID_DIR}
rm -f "${HBASE_PID_DIR}/report-for-duty.ready"

ZOOKEEPER_WAIT_TIMEOUT_SECONDS="${ZOOKEEPER_WAIT_TIMEOUT_SECONDS:-300}"
ZOOKEEPER_WAIT_INTERVAL_SECONDS="${ZOOKEEPER_WAIT_INTERVAL_SECONDS:-5}"
ZOOKEEPER_ENDPOINTS_RAW="${ZOOKEEPER_ENDPOINTS:-}"
if [[ -z "${ZOOKEEPER_ENDPOINTS_RAW}" && -n "${ZOOKEEPER_QUORUM:-}" ]]; then
    ZOOKEEPER_ENDPOINTS_RAW="${ZOOKEEPER_QUORUM}:${ZOOKEEPER_CLIENT_PORT:-2181}"
fi

if [[ -z "${ZOOKEEPER_ENDPOINTS_RAW}" ]]; then
    echo "ZooKeeper endpoints are empty, cannot start RegionServer." >&2
    exit 1
fi

echo "Waiting for ZooKeeper readiness before starting RegionServer..."
deadline=$((SECONDS + ZOOKEEPER_WAIT_TIMEOUT_SECONDS))
while true; do
    IFS=',' read -r -a zk_endpoints <<< "${ZOOKEEPER_ENDPOINTS_RAW}"
    for endpoint in "${zk_endpoints[@]}"; do
        endpoint="${endpoint//[[:space:]]/}"
        [[ -z "${endpoint}" ]] && continue
        host="${endpoint%:*}"
        port="${endpoint##*:}"
        if [[ "${host}" == "${port}" ]]; then
            port="${ZOOKEEPER_CLIENT_PORT:-2181}"
        fi
        if exec 3<>/dev/tcp/${host}/${port} 2>/dev/null; then
            exec 3<&-
            exec 3>&-
            echo "ZooKeeper is reachable via ${host}:${port}"
            break 2
        fi
    done
    if (( SECONDS >= deadline )); then
        echo "Timed out waiting for ZooKeeper readiness: ${ZOOKEEPER_ENDPOINTS_RAW}" >&2
        exit 1
    fi
    sleep "${ZOOKEEPER_WAIT_INTERVAL_SECONDS}"
done

function shutdown() {
    echo "[$(date)] Stopping RegionServer gracefully..."
    export HBASE_STOP_TIMEOUT=20

    echo "[$(date)] Stopping RegionServer daemon..."
    ${HBASE_HOME}/bin/hbase-daemon.sh stop regionserver || true
    echo "[$(date)] RegionServer stopped."
}

trap shutdown SIGTERM SIGINT

${HBASE_HOME}/bin/hbase regionserver start &
rs_pid=$!
wait $rs_pid
