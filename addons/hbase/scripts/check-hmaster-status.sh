#!/bin/bash
set -e

HMASTER_INFO_PORT=${HMASTER_INFO_PORT:-16010}

if jps 2>/dev/null | grep -q HMaster; then
    exit 0
fi

if pgrep -f "org.apache.hadoop.hbase.master.HMaster" > /dev/null 2>&1; then
    exit 0
fi

if curl -sf -o /dev/null "http://127.0.0.1:${HMASTER_INFO_PORT}/master-status" 2>/dev/null; then
    exit 0
fi

exit 1
