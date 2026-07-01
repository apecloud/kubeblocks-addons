#!/bin/sh
# Called by KubeBlocks before a replication replica is removed (scale-in).
# Stops replication threads and resets slave configuration so the departing
# pod leaves no stale replication state.

set -e

MARIADB_CLI="${MARIADB_CLI:-mariadb}"
if ! command -v "${MARIADB_CLI}" >/dev/null 2>&1; then
  MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"
  if [ -x "${MYSQL_CLIENT_DIR}/bin/mariadb" ]; then
    MARIADB_CLI="${MYSQL_CLIENT_DIR}/bin/mariadb"
  fi
fi

MEMBER_LEAVE_SQL_USER="${MYSQL_ADMIN_USER:-${MARIADB_ROOT_USER}}"
MEMBER_LEAVE_SQL_PASSWORD="${MYSQL_ADMIN_PASSWORD:-${MARIADB_ROOT_PASSWORD}}"

local_sql() {
  "${MARIADB_CLI}" "-u${MEMBER_LEAVE_SQL_USER}" "-p${MEMBER_LEAVE_SQL_PASSWORD}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -N -s "$@"
}

echo "memberLeave: stopping replication on ${POD_NAME:-this node}..."

cleanup_rc=0
if ! output="$(local_sql -e "STOP SLAVE;" 2>&1)"; then
  echo "memberLeave: STOP SLAVE failed; refusing to report cleanup success: ${output}" >&2
  cleanup_rc=1
fi

if ! output="$(local_sql -e "RESET SLAVE ALL;" 2>&1)"; then
  echo "memberLeave: RESET SLAVE ALL failed; refusing to report cleanup success: ${output}" >&2
  cleanup_rc=1
fi

if [ "${cleanup_rc}" -ne 0 ]; then
  exit "${cleanup_rc}"
fi

echo "memberLeave: replication cleanup complete."
