#!/bin/bash
set -euo pipefail

HMASTER_INFO_PORT="${HMASTER_INFO_PORT:-${HBASE_MASTER_INFO_PORT:-16010}}"

curl -sf --max-time 2 -o /dev/null "http://127.0.0.1:${HMASTER_INFO_PORT}/master-status"
