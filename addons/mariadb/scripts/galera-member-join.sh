#!/bin/sh
# Called by KubeBlocks when a new member is joining the Galera cluster.
# Waits until galera-start.sh signals that this node has reached wsrep_local_state=4 (Synced).
#
# NOTE: kbagent (which executes this script) has no mariadb binary.
# galera-start.sh writes .galera-synced once wsrep_local_state=4 is detected via Unix socket.
# This script simply checks for that file.

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
SYNCED_FILE="${DATA_DIR}/.galera-synced"
MAX_WAIT=3600
INTERVAL=5
elapsed=0

echo "Waiting for Galera SST to complete on ${KB_JOIN_MEMBER_POD_NAME:-this node}..."

while true; do
  if [ -f "${SYNCED_FILE}" ]; then
    echo "Node synced (${SYNCED_FILE} present). Member join complete."
    exit 0
  fi
  if [ "$elapsed" -ge "$MAX_WAIT" ]; then
    echo "Timeout waiting for node to sync after ${MAX_WAIT}s."
    exit 1
  fi
  sleep "$INTERVAL"
  elapsed=$((elapsed + INTERVAL))
done
