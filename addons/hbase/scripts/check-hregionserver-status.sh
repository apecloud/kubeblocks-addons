#!/bin/bash
set -e

REGIONSERVER_INFO_PORT=${REGIONSERVER_INFO_PORT:-16030}

if jps 2>/dev/null | grep -q HRegionServer; then
    exit 0
fi

if pgrep -f "org.apache.hadoop.hbase.regionserver.HRegionServer" > /dev/null 2>&1; then
    exit 0
fi

if curl -sf -o /dev/null "http://127.0.0.1:${REGIONSERVER_INFO_PORT}/rs-status" 2>/dev/null; then
    exit 0
fi

exit 1
