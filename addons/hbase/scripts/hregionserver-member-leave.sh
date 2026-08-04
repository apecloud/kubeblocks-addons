#!/usr/bin/env bash
set -euo pipefail

: "${HBASE_HOME:=/opt/hbase}"

REGIONSERVER_HOST="${KB_LEAVE_MEMBER_POD_FQDN:-${KB_LEAVE_MEMBER_POD_NAME:-}}"
if [[ -z "${REGIONSERVER_HOST}" ]]; then
  echo "KB_LEAVE_MEMBER_POD_FQDN or KB_LEAVE_MEMBER_POD_NAME is required" >&2
  exit 1
fi

# ponytail: memberLeave only does RegionMover unload; add balancer coordination later only if unload alone proves insufficient in production.
echo "Unloading regions from ${REGIONSERVER_HOST}..."
"${HBASE_HOME}/bin/hbase" org.apache.hadoop.hbase.util.RegionMover -m 6 -r "${REGIONSERVER_HOST}" -o unload
echo "RegionServer ${REGIONSERVER_HOST} unloaded"
