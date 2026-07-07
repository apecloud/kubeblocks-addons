#!/usr/bin/env bash
set -o errexit
set -o errtrace
set -o nounset
set -o pipefail

: "${HADOOP_HOME:=/opt/hadoop}"
: "${HADOOP_CONF_DIR:=${HADOOP_HOME}/etc/hadoop}"
export HADOOP_HOME HADOOP_CONF_DIR

EXCLUDE_FILE="${HADOOP_CONF_DIR}/dfs.exclude"
CURRENT_HOST=$(hostname -f 2>/dev/null || hostname)

echo "[$(date)] Starting DataNode decommission for ${CURRENT_HOST}..."

if [[ -f "$EXCLUDE_FILE" ]]; then
    if grep -q "${CURRENT_HOST}" "$EXCLUDE_FILE" 2>/dev/null; then
        echo "[$(date)] Host already in exclude file"
    else
        echo "${CURRENT_HOST}" >> "$EXCLUDE_FILE"
    fi
else
    echo "${CURRENT_HOST}" > "$EXCLUDE_FILE"
fi

"${HADOOP_HOME}/bin/hdfs" dfsadmin -refreshNodes || true

echo "[$(date)] Waiting for decommission to complete (max wait 300s)..."
for i in $(seq 1 60); do
    DECOMM_STATUS=$("${HADOOP_HOME}/bin/hdfs" dfsadmin -report 2>/dev/null | grep -A 5 "Name: ${CURRENT_HOST}" | grep "Decommission Status" | head -1 || echo "")
    if echo "$DECOMM_STATUS" | grep -q "Decommissioned"; then
        echo "[$(date)] DataNode ${CURRENT_HOST} successfully decommissioned"
        exit 0
    fi
    sleep 5
done

echo "[$(date)] Decommission wait timed out, proceeding with shutdown anyway"
exit 0
