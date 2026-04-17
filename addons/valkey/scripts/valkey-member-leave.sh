#!/bin/bash
# valkey-member-leave.sh — memberLeave lifecycle action.
#
# Called by KubeBlocks when a pod is being removed from the component
# (scale-in, pod eviction).  KubeBlocks injects:
#   KB_LEAVE_MEMBER_POD_NAME  — name of the pod being removed
#   KB_LEAVE_MEMBER_POD_FQDN — FQDN of the pod being removed
#
# When Sentinel is present:
#   - If the leaving pod is a secondary: call SENTINEL RESET to clean up
#     stale replica entries so Sentinel doesn't wait on a dead pod.
#   - If the leaving pod is the current primary: trigger SENTINEL FAILOVER
#     first so Sentinel promotes a new primary before this pod goes away.
#
# When Sentinel is absent (standalone): nothing to do.

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
  local cmd="valkey-cli --no-auth-warning -h ${host} -p ${port}"
  [ -n "${VALKEY_DEFAULT_PASSWORD}" ] && cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  [ -n "${VALKEY_CLI_TLS_ARGS}" ]     && cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  echo "${cmd}"
}

build_sentinel_cli() {
  local host="${1}"
  local cmd="valkey-cli --no-auth-warning -h ${host} -p ${sentinel_port}"
  [ -n "${SENTINEL_PASSWORD}" ] && cmd="${cmd} -a ${SENTINEL_PASSWORD}"
  [ -n "${VALKEY_CLI_TLS_ARGS}" ] && cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  echo "${cmd}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library

if is_empty "${SENTINEL_COMPONENT_NAME}" || is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  echo "No Sentinel component — nothing to do on member leave."
  exit 0
fi

if is_empty "${KB_LEAVE_MEMBER_POD_FQDN}"; then
  echo "KB_LEAVE_MEMBER_POD_FQDN not set — skipping." >&2
  exit 0
fi

master_name="${VALKEY_COMPONENT_NAME}"
leaving_fqdn="${KB_LEAVE_MEMBER_POD_FQDN}"

# Determine the role of the leaving pod
_data_cli=$(build_data_cli "${leaving_fqdn}")
leaving_role=$(${_data_cli} INFO replication 2>/dev/null \
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
  _s_cli=$(build_sentinel_cli "${s}")
  if ${_s_cli} PING 2>/dev/null | grep -q "PONG"; then
    epoch=$(${_s_cli} SENTINEL masters 2>/dev/null \
              | awk '/^config-epoch$/{getline; gsub(/\r/,""); print; exit}')
    epoch="${epoch:-0}"
    if [ "${epoch}" -gt "${best_epoch}" ]; then
      best_epoch="${epoch}"
      sentinel_fqdn="${s}"
    fi
  fi
done

if is_empty "${sentinel_fqdn}"; then
  echo "WARNING: no reachable Sentinel — skipping." >&2
  exit 0
fi

echo "Using sentinel ${sentinel_fqdn} (config-epoch=${best_epoch})"
s_cli=$(build_sentinel_cli "${sentinel_fqdn}")

# Resolve the leaving pod's IP once for all comparisons below.
leaving_ip=$(getent hosts "${leaving_fqdn}" 2>/dev/null | awk '{print $1}' | head -n1) || true

_sentinel_master_is_leaving() {
  # Returns 0 (true) when the chosen sentinel reports the leaving pod as master.
  local sm
  sm=$(${s_cli} SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null \
         | head -n1 | tr -d '\r\n') || true
  if is_empty "${sm}" || [ "${sm}" = "(nil)" ]; then
    return 1   # sentinel doesn't know — treat as "not leaving"
  fi
  if contains "${sm}" "${KB_LEAVE_MEMBER_POD_NAME}." || \
     { ! is_empty "${leaving_ip}" && [ "${sm}" = "${leaving_ip}" ]; }; then
    return 0   # still points at the leaving pod
  fi
  return 1
}

# do_sentinel_reset tracks whether to call SENTINEL RESET after memberLeave.
# SENTINEL RESET tells sentinel to drop its known-replica list and rediscover
# the topology.  It MUST NOT be called before the pod is actually removed
# (i.e. never call it as a side-effect of the "sentinel already moved on" fast
# path) because it temporarily zeros num-slaves — any pod that restarts during
# that window may fail quorum and fall through to the heuristic path, which can
# create a second standalone master.
#
# Policy:
#  - leaving_role == "master" AND sentinel still points at leaving pod:
#      call FAILOVER, wait for new master, then call RESET (so sentinel cleans
#      up the newly-demoted master).
#  - leaving_role == "master" AND sentinel already moved on (fast-path):
#      skip FAILOVER AND skip RESET.  KubeBlocks removes the pod next;
#      sentinel will naturally mark it as s_down/o_down and prune it.
#  - leaving_role == "slave" (non-master):
#      skip FAILOVER AND skip RESET.  Same reasoning — premature RESET
#      disrupts quorum for remaining pods.  Sentinel will self-clean once
#      the pod is gone (within down-after-milliseconds + replica-timeout).
do_sentinel_reset=false

if [ "${leaving_role}" = "master" ]; then
  # Double-check sentinel's current opinion before issuing FAILOVER.
  # KubeBlocks calls switchover before memberLeave; if the chosen sentinel
  # already reports a different master the failover is done — skip both
  # FAILOVER and RESET (sentinel auto-cleans when the pod actually goes away).
  if _sentinel_master_is_leaving; then
    echo "Leaving pod is the primary per sentinel — triggering SENTINEL FAILOVER first..."
    # valkey-cli exits 0 even for protocol errors; capture output and log it.
    failover_out=$(${s_cli} SENTINEL FAILOVER "${master_name}" 2>&1) || true
    echo "SENTINEL FAILOVER response: ${failover_out}"
    case "${failover_out}" in
      *"ERR"*|*"error"*|*"BUSY"*)
        echo "WARNING: SENTINEL FAILOVER rejected — ${failover_out}" >&2 ;;
    esac
    # Wait up to 30 s for a new primary to emerge
    failover_done=false
    for _ in $(seq 1 10); do
      sleep 3
      new_master=$(${s_cli} SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null \
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
        do_sentinel_reset=true
        break
      fi
    done
    if [ "${failover_done}" = "false" ]; then
      echo "WARNING: failover still in progress after 30s — skipping SENTINEL RESET to avoid interfering." >&2
    fi
  else
    echo "Sentinel already reports a different master — skipping SENTINEL FAILOVER and SENTINEL RESET."
    # Sentinel will self-clean when the pod is deleted by KubeBlocks.
  fi
fi

# Ask Sentinel to refresh its knowledge of replicas only after a FAILOVER has
# been confirmed.  See policy comment above for why RESET is skipped otherwise.
if [ "${do_sentinel_reset}" = "true" ]; then
  echo "Issuing SENTINEL RESET ${master_name} on all Sentinels..."
  for s in "${sentinel_fqdns[@]}"; do
    _r_cli=$(build_sentinel_cli "${s}")
    reset_out=$(${_r_cli} SENTINEL RESET "${master_name}" 2>/dev/null) || true
    echo "SENTINEL RESET ${master_name} on ${s}: ${reset_out}"
  done
fi

echo "Member leave handling complete."
