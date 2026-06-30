#!/bin/bash
# valkey-member-leave.sh — memberLeave lifecycle action.
#
# Called by KubeBlocks when a pod is being removed from the component
# (scale-in, pod eviction).  KubeBlocks injects:
#   KB_LEAVE_MEMBER_POD_NAME  — name of the pod being removed
#   KB_LEAVE_MEMBER_POD_FQDN — FQDN of the pod being removed
#
# When Sentinel is present:
#   - If the leaving pod is a secondary: no Sentinel action is needed.
#     Sentinel auto-detects the pod going down and excludes it from quorum
#     and election decisions via down-after-milliseconds + replica-timeout.
#   - If the leaving pod is the current primary: trigger SENTINEL FAILOVER
#     first so Sentinel promotes a new primary before this pod goes away.
#
# When Sentinel is absent: fail closed unless the leaving pod is confirmed to
# be a replica. A primary leave without Sentinel cannot be made safe here.
#
# Note: SENTINEL RESET is intentionally NOT called from this script. See the
# detailed comment above the master-leave block for rationale.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${SERVICE_PORT:-6379}"

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"

build_data_cli() {
  local host="${1}"
  _data_cli_cmd=(valkey-cli --no-auth-warning -h "${host}" -p "${port}")
  if [ -n "${VALKEY_DEFAULT_PASSWORD}" ]; then
    _data_cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
    # shellcheck disable=SC2206
    _data_cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

build_sentinel_cli() {
  local host="${1}"
  _sentinel_cli_cmd=(valkey-cli --no-auth-warning -h "${host}" -p "${sentinel_port}")
  if [ -n "${SENTINEL_PASSWORD}" ]; then
    _sentinel_cli_cmd+=(-a "${SENTINEL_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS}" ]; then
    # shellcheck disable=SC2206
    _sentinel_cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# Fail-closed safety check: when no Sentinel is reachable, only allow
# member-leave to succeed if the leaving pod is a confirmed replica.
# Returns 0 for slave, 1 for master/unknown/empty.
no_sentinel_safety_check() {
  local role="$1"
  if [ "${role}" = "slave" ]; then
    echo "WARNING: no reachable Sentinel — skipping (leaving pod is a confirmed replica)." >&2
    return 0
  fi
  echo "ERROR: no reachable Sentinel and the leaving pod role is ${role:-unknown} — cannot ensure safe failover." >&2
  return 1
}

sentinel_master_state() {
  # Prints one of:
  #   leaving   - Sentinel still reports the leaving pod as master
  #   different - Sentinel reports another concrete master
  #   unknown   - Sentinel has no concrete master answer
  local sm
  sm=$("${s_cli[@]}" SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null \
         | head -n1 | tr -d '\r\n') || true
  if is_empty "${sm}" || [ "${sm}" = "(nil)" ]; then
    echo "unknown"
    return 0
  fi
  if contains "${sm}" "${KB_LEAVE_MEMBER_POD_NAME}." || \
     { ! is_empty "${leaving_ip}" && [ "${sm}" = "${leaving_ip}" ]; }; then
    echo "leaving"
    return 0
  fi
  echo "different"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library

if is_empty "${SENTINEL_COMPONENT_NAME}" || is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  if is_empty "${KB_LEAVE_MEMBER_POD_FQDN}"; then
    echo "ERROR: no Sentinel component and KB_LEAVE_MEMBER_POD_FQDN is not set — cannot prove memberLeave is safe." >&2
    exit 1
  fi
  build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}"
  leaving_role=$("${_data_cli_cmd[@]}" INFO replication 2>/dev/null \
                   | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
  echo "Leaving pod: ${KB_LEAVE_MEMBER_POD_FQDN}, role: ${leaving_role:-unknown}"
  no_sentinel_safety_check "${leaving_role}"
  exit $?
fi

if is_empty "${KB_LEAVE_MEMBER_POD_FQDN}"; then
  echo "KB_LEAVE_MEMBER_POD_FQDN not set — skipping." >&2
  exit 0
fi

master_name="${VALKEY_COMPONENT_NAME}"
leaving_fqdn="${KB_LEAVE_MEMBER_POD_FQDN}"

# Determine the role of the leaving pod
build_data_cli "${leaving_fqdn}"
leaving_role=$("${_data_cli_cmd[@]}" INFO replication 2>/dev/null \
                 | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true

echo "Leaving pod: ${leaving_fqdn}, role: ${leaving_role:-unknown}"

# Pick the most up-to-date reachable Sentinel (highest config-epoch).
# Using config-epoch avoids choosing an isolated/stale sentinel that has
# fallen behind after repeated failovers — stale sentinels have no slaves
# and will reject or silently no-op SENTINEL FAILOVER requests.
sentinel_fqdn=""
best_epoch=-1
IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
for s in "${sentinel_fqdns[@]}"; do
  build_sentinel_cli "${s}"
  if "${_sentinel_cli_cmd[@]}" PING 2>/dev/null | grep -q "PONG"; then
    epoch=$("${_sentinel_cli_cmd[@]}" SENTINEL masters 2>/dev/null \
              | awk '/^config-epoch$/{getline; gsub(/\r/,""); print; exit}')
    epoch="${epoch:-0}"
    if [ "${epoch}" -gt "${best_epoch}" ]; then
      best_epoch="${epoch}"
      sentinel_fqdn="${s}"
    fi
  fi
done

if is_empty "${sentinel_fqdn}"; then
  no_sentinel_safety_check "${leaving_role}"
  exit $?
fi

echo "Using sentinel ${sentinel_fqdn} (config-epoch=${best_epoch})"
build_sentinel_cli "${sentinel_fqdn}"
s_cli=("${_sentinel_cli_cmd[@]}")

# Resolve the leaving pod's IP once for all comparisons below.
leaving_ip=$(getent hosts "${leaving_fqdn}" 2>/dev/null | awk '{print $1}' | head -n1) || true

# Policy: never call SENTINEL RESET on member leave.
#
# SENTINEL RESET tells a sentinel to drop its known-replica AND known-sentinel
# lists and rediscover the topology via INFO replication and SENTINEL HELLO.
# The previous version of this script called RESET on every sentinel after a
# FAILOVER to "clean up the demoted master" entry from the slaves list. Two
# problems were observed in 12h smoke testing:
#
#   1) RESET temporarily zeros num-other-sentinels. Pub/sub HELLO normally
#      re-discovers other sentinels within seconds, but in roughly 17 percent
#      of master-removal scale-in runs the re-discovery did not complete in
#      time. The stuck sentinel kept reporting the deleted (pre-failover)
#      master. A slave that queried the stuck sentinel got a stale "master
#      is the deleted pod" answer and bound to a non-existent address,
#      leaving the cluster in a 1-master + 1-good-slave + 1-stuck-slave
#      topology that the cascade self-heal daemon could not repair: the
#      stuck slave's master_host pointed to a DNS-NXDOMAIN host, so the
#      daemon's remote-master-unreachable guard correctly skipped the
#      repair attempt. (Issuing REPLICAOF on stale data is the failure
#      mode the guard exists to prevent.)
#
#   2) RESET temporarily zeros num-slaves. Any pod that restarts during this
#      window may fail quorum and fall through to the heuristic bootstrap
#      path, which can create a second standalone master.
#
# The benefit RESET was buying — synchronous removal of the demoted master
# from sentinel's slaves list — is unnecessary. Sentinel naturally marks the
# deleted pod as s_down after down-after-milliseconds and excludes it from
# all quorum and election decisions. The s_down ghost entry stays visible in
# `SENTINEL slaves <master>` output (cosmetic only) until the next sentinel
# restart, which is the standard behaviour of any production Redis sentinel
# deployment.
#
# Trade-off summary:
#   - Skip RESET (this version): cosmetic ghost slave entry until sentinel
#     restart, no functional impact on failover, client routing, scale-out,
#     scale-in, or self-heal.
#   - Call RESET (previous behaviour): roughly 17 percent chance of stuck
#     slave bound to deleted master via stale sentinel answer (real
#     functional break observed in 12h smoke run R6).
#
# Behaviour for each leave path:
#   - leaving_role == "master" AND sentinel still points at leaving pod:
#       call FAILOVER, wait for new master to be confirmed, then return.
#       Sentinel itself transitions the demoted master to s_down via
#       down-after-milliseconds.
#   - leaving_role == "master" AND sentinel already moved on (fast-path):
#       skip FAILOVER. KubeBlocks removes the pod next; sentinel naturally
#       marks it s_down and excludes it from decisions.
#   - leaving_role == "slave" (non-master):
#       no sentinel action needed. Sentinel self-cleans once the pod is gone.

if [ "${leaving_role}" = "master" ]; then
  # Double-check sentinel's current opinion before issuing FAILOVER.
  # KubeBlocks calls switchover before memberLeave; if the chosen sentinel
  # already reports a different master the failover is done — skip FAILOVER
  # (sentinel auto-cleans when the pod actually goes away).
  sentinel_state=$(sentinel_master_state)
  if [ "${sentinel_state}" = "leaving" ]; then
    echo "Leaving pod is the primary per sentinel — triggering SENTINEL FAILOVER first..."
    # valkey-cli exits 0 even for protocol errors; capture output and log it.
    failover_out=$("${s_cli[@]}" SENTINEL FAILOVER "${master_name}" 2>&1) || true
    echo "SENTINEL FAILOVER response: ${failover_out}"
    case "${failover_out}" in
      *"ERR"*|*"error"*|*"BUSY"*)
        echo "ERROR: SENTINEL FAILOVER rejected — ${failover_out}" >&2
        exit 1 ;;
    esac
    # Wait up to 30 s for a new primary to emerge
    failover_done=false
    for _ in $(seq 1 10); do
      sleep 3
      new_master=$("${s_cli[@]}" SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null \
                     | head -n1 | tr -d '\r\n') || true
      # Accept the failover as complete when Sentinel reports a master that is
      # neither the leaving pod's IP nor its pod name/FQDN fragment.
      # Append "." so "valkey-1." does not match "valkey-10.headless...".
      if ! is_empty "${new_master}" && \
         [ "${new_master}" != "(nil)" ] && \
         ! contains "${new_master}" "${KB_LEAVE_MEMBER_POD_NAME}." && \
         { is_empty "${leaving_ip}" || [ "${new_master}" != "${leaving_ip}" ]; }; then
        echo "New primary elected: ${new_master}"
        failover_done=true
        break
      fi
    done
    if [ "${failover_done}" = "false" ]; then
      echo "ERROR: failover still in progress after 30s — refusing memberLeave success while the leaving pod is still master." >&2
      exit 1
    fi
  elif [ "${sentinel_state}" = "different" ]; then
    echo "Sentinel already reports a different master — skipping SENTINEL FAILOVER. Sentinel will self-clean when the pod is deleted by KubeBlocks."
  else
    echo "ERROR: Sentinel returned no concrete master for ${master_name}; refusing memberLeave success while leaving pod is locally master." >&2
    exit 1
  fi
fi

echo "Member leave handling complete."
