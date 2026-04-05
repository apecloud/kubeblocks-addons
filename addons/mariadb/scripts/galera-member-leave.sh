#!/bin/bash
# Called by KubeBlocks before a Galera node is removed.
# Perform a graceful eviction: flush tables and let the cluster
# detect the node's departure via keepalive timeout.

set -eo pipefail

MARIADB_CMD=(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -P3306 -h127.0.0.1 -s)

echo "Gracefully evicting ${POD_NAME:-this node} from Galera cluster..."

# Flush tables to ensure a clean state before shutdown
"${MARIADB_CMD[@]}" -e "FLUSH TABLES;" 2>/dev/null || true

# Set wsrep_desync=ON to avoid being selected as a SST donor during shutdown
"${MARIADB_CMD[@]}" -e "SET GLOBAL wsrep_desync=ON;" 2>/dev/null || true

echo "Member leave preparation complete. Node will be evicted on shutdown."
exit 0
