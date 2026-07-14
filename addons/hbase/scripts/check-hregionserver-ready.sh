#!/bin/bash
set -euo pipefail

REGIONSERVER_INFO_PORT="${REGIONSERVER_INFO_PORT:-${HBASE_REGIONSERVER_INFO_PORT:-16030}}"

curl -sf --max-time 2 -o /dev/null "http://127.0.0.1:${REGIONSERVER_INFO_PORT}/rs-status"
