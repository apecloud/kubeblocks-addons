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
#     restart trigger. Runs sync-inline because it does only one local INFO
#     call (~10ms) and never touches a remote pod, so it cannot block the
#     roleProbe latency budget.
#   - cascade-topology repair: NOT here. Cascade detection requires a
#     remote INFO call to the configured master, which historically blocked
#     roleProbe under failover races. It now runs in
#     valkey-cascade-self-heal.sh as a long-running daemon spawned at
#     valkey-start.sh entrypoint, in the valkey container. Same idiom as
#     clickhouse / mariadb-galera / postgresql startup daemons. Single
#     fork at container lifetime → no zombie accumulation. PR #2615
#     cascade guards (skip-stale-role / skip-self-target) live with the
#     cascade function in the daemon file.

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
#
# Implementation note (Pattern B avoidance):
#   The previous version parsed INFO output with two 4-stage pipelines
#   (`echo|grep|tr|cut`). When the kbagent-driven roleProbe SIGKILLs this
#   script for exceeding timeoutSeconds (e.g. under upgrade or reconfigure
#   load), each pipeline's child processes are reparented to kbagent (PID 1,
#   Go binary, non-reaper) and accumulate as zombies (~8 children leaked
#   per timeout event). See addon-probe-script-fork-and-zombie-guide.md
#   Pattern B + 4D audit checklist; this function previously sat in cell
#   (kbagent-scheduled, B, high-freq, non-reaper) = LEAK.
#
#   The implementation below uses a single bash builtin loop with a
#   here-string, no external processes, so no children can be left
#   parentless when SIGKILL fires.
check_sync_stall() {
  local repl_info sync_in_progress read_bytes line key val
  repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0

  # Single-process parse: bash builtins only, no pipeline / cmd-substitution
  # children that could be orphaned by a kbagent SIGKILL on script timeout.
  sync_in_progress=""
  read_bytes=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "${line}" in
      master_sync_in_progress:*) sync_in_progress="${line#master_sync_in_progress:}" ;;
      master_sync_read_bytes:*) read_bytes="${line#master_sync_read_bytes:}" ;;
    esac
  done <<<"${repl_info}"

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
    # printf %s avoids the trailing newline that `echo` adds — KubeBlocks
    # roleProbe rejects label values containing '\n' (Kubernetes label
    # validation), surfacing as transient `RoleProbeNotDone` and
    # `invalid label value primary\n` events under load.
    printf %s "secondary"
    # check_sync_stall is sync-inline (1 local INFO call, no remote, no
    # blocking risk). cascade detection lives in valkey-cascade-self-heal.sh
    # as a daemon spawned from valkey-start.sh — no roleProbe latency
    # impact and no kbagent-side fork-zombie exposure.
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
