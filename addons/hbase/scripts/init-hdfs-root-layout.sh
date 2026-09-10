#!/bin/bash
set -e

source ${HBASE_CONF_DIR}/hbase-env.sh 2>/dev/null || true
mkdir -p ${HBASE_LOG_DIR}

echo "[$(date)] Initializing HBase root layout in HDFS..."

PATHS=(
    "/${HBASE_ROOT_DIR}"
    "/${HBASE_ROOT_DIR}/WALs"
    "/${HBASE_ROOT_DIR}/data"
    "/${HBASE_ROOT_DIR}/archive"
    "/${HBASE_ROOT_DIR}/.tmp"
    "/${HBASE_ROOT_DIR}/MasterData"
    "/${HBASE_ROOT_DIR}/MasterData/WALs"
)

for p in "${PATHS[@]}"; do
    if timeout 30 ${HBASE_HOME}/bin/hbase org.apache.hadoop.fs.FsShell -test -e "${p}" 2>/dev/null; then
        echo "[$(date)] Path ${p} already exists, skipping."
    else
        echo "[$(date)] Creating ${p}..."
        timeout 30 ${HBASE_HOME}/bin/hbase org.apache.hadoop.fs.FsShell -mkdir -p "${p}"
    fi
done

echo "[$(date)] HBase root layout initialized."
