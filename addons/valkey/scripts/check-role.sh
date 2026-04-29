#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#   The contract is simple: print exactly one line to stdout — the role name
#   that matches one of the roles[] entries in ComponentDefinition.
#
#   For Valkey (Redis-compatible):
#     INFO replication → role:master  →  print "primary"
#     INFO replication → role:slave   →  print "secondary"
#
#   Using valkey-cli (not redis-cli) because Valkey ships its own CLI.
#   The -h 127.0.0.1 ensures we hit this pod's own server.
#
#   KB_SERVICE_PORT and KB_HOST_IP are injected by the roleProbe env[] block
#   in the ComponentDefinition (not from vars[]).
#
# Stall detection (Bug 5 fix):
#   When a slave is in full-sync (master_sync_in_progress=1) but no data is
#   arriving (master_sync_read_bytes=0), and this persists for >STALL_THRESHOLD_SECONDS,
#   we restart the container by sending SIGTERM to PID 1.
#   This handles the race condition in repl-diskless-sync that causes permanent stalls
#   after rapid A→B→C failover sequences.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
STALL_THRESHOLD_SECONDS="${STALL_THRESHOLD_SECONDS:-60}"
STALL_MARKER_FILE="/tmp/valkey_sync_stall_since"

build_cli_cmd() {
  local cmd="valkey-cli --no-auth-warning -h 127.0.0.1 -p ${port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  fi
  echo "${cmd}"
}

# is_self_host — returns 0 if the given host resolves to the current pod.
# Used as a guard before issuing REPLICAOF so cascade-repair never points us
# at ourselves when the chain happens to fold back (A → B → A).
is_self_host() {
  local host="${1%.}"
  local current_pod="${CURRENT_POD_NAME:-}"
  local current_fqdn="${KB_POD_FQDN%.}"

  case "${host}" in
    "127.0.0.1"|"localhost"|"::1")
      return 0
      ;;
  esac

  if [ -n "${current_pod}" ]; then
    [ "${host}" = "${current_pod}" ] && return 0
    contains "${host}" "${current_pod}." && return 0
  fi
  [ -n "${current_fqdn}" ] && [ "${host}" = "${current_fqdn}" ] && return 0

  if command -v getent >/dev/null 2>&1 && [ -n "${current_fqdn}" ]; then
    local host_ips current_ips ip
    host_ips=$(getent hosts "${host}" 2>/dev/null | awk '{print $1}' | sort -u) || true
    current_ips=$(getent hosts "${current_fqdn}" 2>/dev/null | awk '{print $1}' | sort -u) || true
    for ip in ${host_ips}; do
      echo "${current_ips}" | grep -qx "${ip}" && return 0
    done
  fi

  return 1
}

# check_cascade_topology — called when this pod is a slave.
# Detects cascading replication (slave of slave) and self-corrects by issuing
# REPLICAOF directly to the real master.  This handles the window after a
# rolling restart where one pod transiently connects to a slave instead of the
# master because sentinel's REPLICAOF broadcast arrived while the pod was still
# starting.  Sentinel does not auto-correct cascading topologies.
check_cascade_topology() {
  local repl_info master_host master_link_status
  repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0

  master_host=$(echo "${repl_info}" | grep "^master_host:" | tr -d '\r\n' | cut -d: -f2)
  master_link_status=$(echo "${repl_info}" | grep "^master_link_status:" | tr -d '\r\n' | cut -d: -f2)

  is_empty "${master_host}" && return 0
  # Run cascade check regardless of link status — if our configured master is itself a slave
  # (cascade), we must redirect even while the link is still connecting or down.
  # If the master is unreachable, the remote CLI returns empty role and we skip safely.

  # Query our master to check its role.
  local remote_cli="valkey-cli --no-auth-warning -h ${master_host} -p ${port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    remote_cli="${remote_cli} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    remote_cli="${remote_cli} ${VALKEY_CLI_TLS_ARGS}"
  fi

  local master_role
  master_role=$(${remote_cli} info replication 2>/dev/null \
    | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || return 0
  [ "${master_role}" != "slave" ] && return 0

  # Our master is itself a slave — cascading topology detected.
  # Follow the chain to find the real master and reconnect directly.
  local master_repl_info real_master_host real_master_port
  master_repl_info=$(${remote_cli} info replication 2>/dev/null) || return 0
  real_master_host=$(echo "${master_repl_info}" | grep "^master_host:" | tr -d '\r\n' | cut -d: -f2)
  real_master_port=$(echo "${master_repl_info}" | grep "^master_port:" | tr -d '\r\n' | cut -d: -f2)

  is_empty "${real_master_host}" && return 0

  # Guard 1 — stale-role race: between the time we read role:slave at the start
  # of the probe and now, Sentinel may have promoted this pod to master. Issuing
  # REPLICAOF on a fresh master would demote it. Re-read local role and skip if
  # we are no longer a slave.
  local current_repl_info current_role
  current_repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0
  current_role=$(echo "${current_repl_info}" | grep "^role:" | tr -d '\r\n' | cut -d: -f2)
  if [ "${current_role}" != "slave" ]; then
    echo "INFO: skip cascade repair (skip-stale-role): local role is '${current_role:-unknown}', not slave." >&2
    return 0
  fi

  # Guard 2 — self-target: the chain may fold back to ourselves (A → B → A
  # during overlapping promotions). Issuing REPLICAOF self is a no-op the
  # server rejects, but emitting it is misleading and pollutes the log.
  if is_self_host "${real_master_host}"; then
    echo "WARNING: skip cascade repair (skip-self-target): target ${real_master_host}:${real_master_port:-${port}} resolves to current pod ${CURRENT_POD_NAME:-unknown}." >&2
    return 0
  fi

  echo "WARNING: cascading topology — our master ${master_host} is a slave of ${real_master_host}. Issuing REPLICAOF to reconnect directly to real master." >&2
  ${cli_cmd} REPLICAOF "${real_master_host}" "${real_master_port:-${port}}" 2>/dev/null || true
}

# check_sync_stall — called when this pod is a slave.
# Detects the diskless full-sync stall described in Bug 5:
#   master_sync_in_progress=1 AND master_sync_read_bytes=0 for > STALL_THRESHOLD_SECONDS
# Action: send SIGTERM to PID 1 to trigger a container restart.
check_sync_stall() {
  local repl_info sync_in_progress read_bytes
  repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0

  sync_in_progress=$(echo "${repl_info}" | grep "^master_sync_in_progress:" | tr -d '\r\n' | cut -d: -f2)
  read_bytes=$(echo "${repl_info}" | grep "^master_sync_read_bytes:" | tr -d '\r\n' | cut -d: -f2)

  if [ "${sync_in_progress}" = "1" ] && [ "${read_bytes}" = "0" ]; then
    if [ ! -f "${STALL_MARKER_FILE}" ]; then
      date +%s > "${STALL_MARKER_FILE}"
      echo "WARNING: full-sync stall detected (master_sync_read_bytes=0), started tracking." >&2
      return 0
    fi
    local stall_since elapsed
    stall_since=$(cat "${STALL_MARKER_FILE}" 2>/dev/null) || return 0
    elapsed=$(( $(date +%s) - stall_since ))
    if [ "${elapsed}" -ge "${STALL_THRESHOLD_SECONDS}" ]; then
      echo "ERROR: full-sync stall persisted for ${elapsed}s (threshold ${STALL_THRESHOLD_SECONDS}s) — restarting server." >&2
      rm -f "${STALL_MARKER_FILE}"
      restart_server_for_stall_recovery
    else
      echo "WARNING: full-sync stall ongoing for ${elapsed}s / ${STALL_THRESHOLD_SECONDS}s threshold." >&2
    fi
  else
    if [ -f "${STALL_MARKER_FILE}" ]; then
      echo "INFO: full-sync stall resolved, removing marker." >&2
      rm -f "${STALL_MARKER_FILE}"
    fi
  fi
}

restart_server_for_stall_recovery() {
  if [ "${ut_mode}" = "true" ]; then
    echo "ut_mode: would send SIGTERM to PID 1 (valkey-server) to restart container" >&2
    return 0
  fi
  kill -SIGTERM 1
}

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library

cli_cmd=$(build_cli_cmd)

unset_xtrace_when_ut_mode_false
# Strip \r\n — valkey-cli INFO output uses CRLF line endings per Redis protocol.
# Without tr, "role:master\r" would never match the case patterns below.
role_line=$(${cli_cmd} info replication 2>/dev/null \
  | grep "^role:" | tr -d '\r\n')
set_xtrace_when_ut_mode_false

case "${role_line}" in
  "role:master") echo "primary"   ;;
  "role:slave")
    echo "secondary"
    check_cascade_topology || true
    check_sync_stall || true
    ;;
  *)
    echo "unknown role: '${role_line}'" >&2
    # Returning a non-zero exit code tells KubeBlocks the probe failed.
    # KubeBlocks will increment the failure counter and, after
    # failureThreshold is exceeded, clear the role label on this pod.
    exit 1
    ;;
esac
