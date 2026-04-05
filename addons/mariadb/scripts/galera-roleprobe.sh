#!/bin/bash
# Probe Galera node state and report KubeBlocks role.
#
# wsrep_local_state values:
#   1 = Joining        (SST in progress, not ready)
#   2 = Donor/Desynced (sending SST to joiner, can serve reads in some configs)
#   3 = Joined         (catching up via IST)
#   4 = Synced         (fully operational, safe for reads+writes)
#
# We map: 4 -> "primary", anything else -> "secondary"

set -eo pipefail

MARIADB_CMD=(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" -P3306 -h127.0.0.1 -N -s)

state=$("${MARIADB_CMD[@]}" -e "SHOW STATUS LIKE 'wsrep_local_state';" 2>/dev/null | awk '{print $2}')

if [ "$state" = "4" ]; then
  echo -n "primary"
else
  echo -n "secondary"
fi
