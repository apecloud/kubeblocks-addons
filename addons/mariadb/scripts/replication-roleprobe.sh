#!/bin/sh
# Probe replication role from local MariaDB bootstrap state.
# Shebang is /bin/sh (not bash) because the kbagent sidecar image only ships
# busybox sh; when kbagent invokes the script via direct exec the kernel
# resolves the shebang, and /bin/bash ENOENT causes a silent exit=1 with empty
# output. Script body must remain POSIX-compatible.
# Return secondary if slave config exists, primary if no slave config.
# While bootstrap is still initializing, fail the probe instead of publishing a
# temporary role. KubeBlocks ignores failed roleProbe events, so pod labels are
# only updated after the local datadir state is stable.
#
# Role is determined by checking the master.info file:
#   - master.info exists  → CHANGE MASTER TO was run → secondary
#   - master.info missing → RESET SLAVE ALL was run (or never configured) → primary
#
# The local datadir state is authoritative for KubeBlocks pod role labels during
# bootstrap. syncerctl/DCS role can lag or be empty before HA lease convergence,
# which can transiently mark every pod secondary and empty the primary Service.
# Primary selection still stays file-based; only secondary publication adds a
# local MariaDB / replication truth gate so stale ready markers cannot keep a
# broken replica published.
#
# NOTE: KubeBlocks roleProbe exec runs in the kbagent execution context. The
# configured `container: mariadb` shares the target container's volume mounts,
# but the probe does not execute inside the mariadb container itself. Therefore
# the shared datadir markers are the authoritative truth once bootstrap is
# stable. For secondary publication we also require current local MariaDB
# reachability plus healthy replication truth so stale ready markers cannot keep
# or republish a broken replica.

data_dir() {
  printf "%s" "${MARIADB_DATADIR:-/var/lib/mysql}"
}

MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"

ready_file() {
  printf "%s/.replication-ready" "$(data_dir)"
}

pending_file() {
  printf "%s/.replication-pending" "$(data_dir)"
}

master_info_file() {
  printf "%s/master.info" "$(data_dir)"
}

resolve_mariadb_cli() {
  if command -v mariadb >/dev/null 2>&1; then
    command -v mariadb
    return 0
  fi
  if [ -x "${MYSQL_CLIENT_DIR}/bin/mariadb" ]; then
    printf "%s" "${MYSQL_CLIENT_DIR}/bin/mariadb"
    return 0
  fi
  return 1
}

local_sql() {
  local mariadb_cli
  mariadb_cli=$(resolve_mariadb_cli) || return 1
  "${mariadb_cli}" "-u${MARIADB_ROOT_USER:-root}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -N -s "$@" 2>/dev/null
}

query_slave_status() {
  local mariadb_cli
  mariadb_cli=$(resolve_mariadb_cli) || return 1
  # SHOW SLAVE STATUS\G must keep field labels; local_sql intentionally uses
  # -N -s for scalar probes and collapses \G output into unlabeled values.
  "${mariadb_cli}" "-u${MARIADB_ROOT_USER:-root}" "${MARIADB_ROOT_PASSWORD:+-p${MARIADB_ROOT_PASSWORD}}" \
    -P3306 -h127.0.0.1 --connect-timeout=5 -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}

not_ready() {
  echo -n "initializing"
  return 1
}

db_ready() {
  if [ "${MARIADB_ROLEPROBE_SKIP_DB_READY:-}" = "true" ]; then
    return 0
  fi
  local_sql -e "SELECT 1" >/dev/null
}

secondary_replication_ready() {
  # alpha.13 P2: rewrote pipeline-based grep checks to shell-builtin case pattern
  # matching to eliminate fork-on-each-check Pattern B zombie risk.
  # Pre-alpha.13 used 4× (printf | grep -q) → 8 forks per probe tick. When kbagent
  # SIGKILLs the script (timeoutSeconds <1s tail), orphan greps reparent to kbagent
  # (Go non-reaper) → zombie accumulation (~0.04%/probe @ 5s cadence in #402 redline).
  # Shell-builtin case has 0 child fork → no zombie residual under SIGKILL.
  local slave_status
  if [ "${MARIADB_ROLEPROBE_SKIP_DB_READY:-}" = "true" ]; then
    return 0
  fi
  slave_status=$(query_slave_status)
  [ -n "${slave_status}" ] || return 1
  case ${slave_status} in
    *"Slave_IO_Running: Yes"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"Slave_SQL_Running: Yes"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"Last_IO_Errno: 0"*) ;;
    *) return 1 ;;
  esac
  case ${slave_status} in
    *"Last_SQL_Errno: 0"*) ;;
    *) return 1 ;;
  esac
}

check_role() {
  # Before the startup command finishes role selection, do not publish a role.
  # Publishing "secondary" here causes secondary -> primary label flips for
  # pod-0, and publishing "primary" before the pending marker exists causes
  # primary -> secondary flips for later pods when syncer prestart is still
  # running.
  if [ -f "$(pending_file)" ] || [ ! -f "$(ready_file)" ]; then
    not_ready
    return $?
  fi

  # Check if slave config exists via master.info file:
  #   - CHANGE MASTER TO writes master.info
  #   - RESET SLAVE ALL deletes master.info
  if [ -f "$(master_info_file)" ]; then
    # Secondary publication needs more than a stale ready marker: if local
    # MariaDB is unreachable or SHOW SLAVE STATUS cannot prove healthy
    # replication, keep the pod unpublished until rejoin truth closes.
    db_ready || { not_ready; return $?; }
    secondary_replication_ready || { not_ready; return $?; }
    echo -n "secondary"
  else
    echo -n "primary"
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

check_role
