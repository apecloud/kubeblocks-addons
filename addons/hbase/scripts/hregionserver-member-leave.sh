#!/usr/bin/env bash
set -euo pipefail

: "${HBASE_HOME:=/opt/hbase}"

REGIONSERVER_HOST="${KB_LEAVE_MEMBER_POD_FQDN:-${KB_LEAVE_MEMBER_POD_NAME:-}}"
if [[ -z "${REGIONSERVER_HOST}" ]]; then
  echo "KB_LEAVE_MEMBER_POD_FQDN or KB_LEAVE_MEMBER_POD_NAME is required" >&2
  exit 1
fi

BALANCER_DISABLED=false

# Restores the HBase balancer after the unload attempt.
# Parameters: none.
# Returns: 0; restoration failures are logged without replacing the unload result.
restore_balancer() {
  if [[ "${BALANCER_DISABLED}" == "true" ]]; then
    echo "Re-enabling balancer after RegionServer unload..."
    printf "balance_switch true\n" | "${HBASE_HOME}/bin/hbase" shell -n 2>/dev/null || echo "Failed to re-enable the balancer" >&2
  fi
}

trap restore_balancer EXIT

echo "Disabling balancer before unloading ${REGIONSERVER_HOST}..."
printf "balance_switch false\n" | "${HBASE_HOME}/bin/hbase" shell -n 2>/dev/null
BALANCER_DISABLED=true

echo "Unloading regions from ${REGIONSERVER_HOST}..."
"${HBASE_HOME}/bin/hbase" org.apache.hadoop.hbase.util.RegionMover -m 6 -r "${REGIONSERVER_HOST}" -o unload
echo "RegionServer ${REGIONSERVER_HOST} unloaded"
