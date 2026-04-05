#!/bin/bash
# Called by KubeBlocks when a new member is joining the Galera cluster.
# Galera handles SST automatically when a new node starts with a valid
# wsrep_cluster_address — no explicit action is needed here.
# We just wait until the joining node reaches wsrep_local_state = 4 (Synced).

set -eo pipefail

MAX_WAIT=300
INTERVAL=5
elapsed=0

echo "Waiting for Galera SST to complete on ${KB_JOIN_MEMBER_POD_NAME:-this node}..."

MARIADB_CMD="mariadb -u${MARIADB_ROOT_USER} -p${MARIADB_ROOT_PASSWORD} -P3306 -h127.0.0.1 -N -s"

while true; do
  state=$($MARIADB_CMD -e "SHOW STATUS LIKE 'wsrep_local_state';" 2>/dev/null | awk '{print $2}' || echo "0")
  if [ "$state" = "4" ]; then
    echo "Node synced (wsrep_local_state=4). Member join complete."
    exit 0
  fi
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "Timeout waiting for node to sync after ${MAX_WAIT}s. Current state: ${state}"
    exit 1
  fi
  echo "wsrep_local_state=${state}, waiting..."
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done
