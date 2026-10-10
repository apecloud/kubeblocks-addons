#!/bin/bash
set -euo pipefail

if jps 2>/dev/null | grep -q HRegionServer; then
    exit 0
fi

if pgrep -f "org.apache.hadoop.hbase.regionserver.HRegionServer" > /dev/null 2>&1; then
    exit 0
fi

exit 1
