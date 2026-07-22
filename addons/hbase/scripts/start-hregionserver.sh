#!/bin/bash
set -e

source ${HBASE_CONF_DIR}/hbase-env.sh 2>/dev/null || true
mkdir -p ${HBASE_LOG_DIR} ${HBASE_PID_DIR}

function shutdown() {
    echo "[$(date)] Stopping RegionServer gracefully..."
    host=$(hostname -f 2>/dev/null || hostname)
    export HBASE_STOP_TIMEOUT=20

    echo "[$(date)] Disabling balancer before region unload..."
    echo "balance_switch false" | ${HBASE_HOME}/bin/hbase shell 2>/dev/null || true

    echo "[$(date)] Unloading regions from ${host}..."
    ${HBASE_HOME}/bin/hbase org.apache.hadoop.hbase.util.RegionMover -m 6 -r ${host} -o unload 2>&1 || true

    sleep 5

    echo "[$(date)] Re-enabling balancer..."
    echo "balance_switch true" | ${HBASE_HOME}/bin/hbase shell 2>/dev/null || true

    echo "[$(date)] Stopping RegionServer daemon..."
    ${HBASE_HOME}/bin/hbase-daemon.sh stop regionserver || true
    echo "[$(date)] RegionServer stopped."
}

trap shutdown SIGTERM SIGINT

${HBASE_HOME}/bin/hbase regionserver start &
rs_pid=$!
wait $rs_pid
