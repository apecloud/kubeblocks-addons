#!/bin/bash
set -euo pipefail

REGIONSERVER_INFO_PORT="${REGIONSERVER_INFO_PORT:-${HBASE_REGIONSERVER_INFO_PORT:-16030}}"
REGIONSERVER_PORT="${HBASE_REGIONSERVER_PORT:-16020}"
REGIONSERVER_HOST="${POD_FQDN:-$(hostname -f 2>/dev/null || hostname)}"
READY_MARKER="${HBASE_PID_DIR:-/tmp/hbase}/report-for-duty.ready"

curl -sf --max-time 2 -o /dev/null "http://127.0.0.1:${REGIONSERVER_INFO_PORT}/rs-status"

# ponytail: HBase Shell is used only until registration is confirmed; replace the marker with a direct JMX signal if HBase exposes one later.
[[ -f "${READY_MARKER}" ]] && exit 0
STATUS_OUTPUT="$(printf "status 'simple'\n" | "${HBASE_HOME}/bin/hbase" shell -n 2>/dev/null)"
grep -Fq "${REGIONSERVER_HOST}:${REGIONSERVER_PORT} " <<< "${STATUS_OUTPUT}"
touch "${READY_MARKER}"
