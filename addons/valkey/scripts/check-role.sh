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
# Self-heal scope on this script:
#   - check_sync_stall (Bug 5 fix): full-sync stall detector + container
#     restart trigger.  Sync-inline because it only does ONE local INFO call
#     (~10ms) and never touches a remote pod.
#   - cascade-topology repair: NOT here.  Cascade detection requires a
#     remote INFO call to the configured master, which historically blocked
#     the roleProbe latency budget under failover races.  An async fork
#     workaround leaked zombies in the kbagent container (kbagent's PID 1
#     is a Go binary that does not reap unrelated children — see
#     docs/addon-probe-script-fork-and-zombie-guide.md).
#     Cascade is now driven by valkey-cascade-self-heal.sh as a long-running
#     daemon spawned at valkey-start.sh entrypoint, in the valkey container.
#     Same pattern as clickhouse / mariadb-galera / postgresql startup
#     daemons.  Single fork at container lifetime → no zombie accumulation.

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
  "role:master") printf %s "primary"   ;;
  "role:slave")
    printf %s "secondary"
    # check_sync_stall is sync-inline (1 local INFO call, fast).
    # Cascade detection lives in valkey-cascade-self-heal.sh, run as a
    # daemon by valkey-start.sh.
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
