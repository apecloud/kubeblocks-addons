#!/bin/bash
set -euo pipefail

if jps 2>/dev/null | grep -q HMaster; then
    exit 0
fi

if pgrep -f "org.apache.hadoop.hbase.master.HMaster" > /dev/null 2>&1; then
    exit 0
fi

exit 1
