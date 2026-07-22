#!/bin/bash
set -e

source ${HBASE_CONF_DIR}/hbase-env.sh 2>/dev/null || true
mkdir -p ${HBASE_LOG_DIR} ${HBASE_PID_DIR}

function shutdown() {
    echo "[$(date)] Stopping HMaster gracefully..."
    ${HBASE_HOME}/bin/hbase-daemon.sh stop master || true
    echo "[$(date)] HMaster stopped."
}

trap shutdown SIGTERM SIGINT

${HBASE_HOME}/bin/hbase master start &
master_pid=$!
wait $master_pid
