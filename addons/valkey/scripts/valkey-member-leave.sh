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
  # shellcheck source=/dev/null
  source /scripts/sentinel-endpoint.sh
}
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
ACTION_CLIENT_TIMEOUT_SECONDS="${ACTION_CLIENT_TIMEOUT_SECONDS:-3}"

member_leave_diagnose() {
  local phase="$1"
  local retry_safe="$2"
  local detail="$3"
  {
    echo "memberLeave diagnosis:"
    echo "  action: memberLeave"
    echo "  phase: ${phase}"
    echo "  cluster: ${KB_CLUSTER_NAME:-<unset>}"
    echo "  detail: ${detail}"
    echo "  next-retry-safe: ${retry_safe}"
  } >&2
}

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

run_data_cli() {
  timeout "${ACTION_CLIENT_TIMEOUT_SECONDS}" "${_data_cli_cmd[@]}" "$@"
}

run_selected_sentinel_cli() {
  timeout "${ACTION_CLIENT_TIMEOUT_SECONDS}" "${s_cli[@]}" "$@"
}

run_sentinel_cli_for_host() {
  local host="$1"
  shift
  build_sentinel_cli "${host}"
  timeout "${ACTION_CLIENT_TIMEOUT_SECONDS}" "${_sentinel_cli_cmd[@]}" "$@"
}

canonicalize_sentinel_endpoints() {
  local raw="$1"
  local endpoint
  local -A seen=()

  sentinel_fqdns=()
  case "${raw}" in
    ""|,*|*,|*,,*)
      return 1
      ;;
  esac

  IFS=',' read -ra raw_sentinel_fqdns <<< "${raw}"
  for endpoint in "${raw_sentinel_fqdns[@]}"; do
    if is_empty "${endpoint}" || [ -n "${seen[${endpoint}]:-}" ]; then
      return 1
    fi
    seen["${endpoint}"]=1
    sentinel_fqdns+=("${endpoint}")
  done
  [ "${#sentinel_fqdns[@]}" -gt 0 ]
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
  #   leaving   - a strict majority still reports the leaving pod as master
  #   different - a strict majority reports the same other concrete master
  #   unknown   - configured Sentinels have no strict-majority answer
  local endpoint reply host reported_port vote_host
  local total="${#sentinel_fqdns[@]}"
  local threshold=$((total / 2))
  local -a fields=()
  local -A votes=()

  if [ "${total}" -eq 0 ]; then
    echo "unknown"
    return 0
  fi

  for endpoint in "${sentinel_fqdns[@]}"; do
    reply=$(run_sentinel_cli_for_host "${endpoint}" \
      SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null) || continue
    mapfile -t fields < <(printf '%s\n' "${reply}" | tr -d '\r' | sed '/^$/d')
    if [ "${#fields[@]}" -ne 2 ]; then
      continue
    fi
    host="${fields[0]}"
    reported_port="${fields[1]}"
    vote_host=$(resolve_sentinel_master_endpoint "${host}" "${reported_port}" member-leave) || continue
    if [ "${vote_host%%.*}" = "${KB_LEAVE_MEMBER_POD_FQDN%%.*}" ]; then
      vote_host="__leaving__"
    fi
    votes["${vote_host}"]=$(( ${votes["${vote_host}"]:-0} + 1 ))
  done

  for vote_host in "${!votes[@]}"; do
    if [ "${votes[${vote_host}]}" -gt "${threshold}" ]; then
      if [ "${vote_host}" = "__leaving__" ]; then
        echo "leaving"
      else
        echo "different"
      fi
      return 0
    fi
  done
  echo "unknown"
}

handle_master_leave() {
  local sentinel_state failover_out failover_rc=0
  sentinel_state=$(sentinel_master_state)
  case "${sentinel_state}" in
    different)
      echo "Sentinel already reports a different master — memberLeave is safe to continue."
      return 0
      ;;
    unknown)
      member_leave_diagnose \
        "master-not-yet-observable" "yes" \
        "Sentinel returned no concrete master for ${master_name}; keeping the leaving primary."
      return 1
      ;;
  esac

  echo "Leaving pod is the primary per Sentinel — triggering SENTINEL FAILOVER..."
  failover_out=$(run_selected_sentinel_cli SENTINEL FAILOVER "${master_name}" 2>&1) || failover_rc=$?
  echo "SENTINEL FAILOVER response: ${failover_out}"
  if [ "${failover_rc}" -ne 0 ]; then
    member_leave_diagnose \
      "failover-transport" "yes" \
      "SENTINEL FAILOVER transport failed with rc=${failover_rc}; no protocol acceptance was observed."
    return 1
  fi
  case "${failover_out}" in
    OK*)
      member_leave_diagnose \
        "failover-issued" "yes" \
        "Sentinel accepted failover; a later invocation must observe a different master."
      return 1
      ;;
    *"BUSY"*|*"INPROG"*)
      member_leave_diagnose \
        "failover-in-progress" "yes" \
        "Sentinel reports an existing failover; a later invocation must confirm its result."
      return 1
      ;;
    *)
      member_leave_diagnose \
        "failover-rejected" "no" \
        "SENTINEL FAILOVER returned ${failover_out:-<empty>}."
      return 1
      ;;
  esac
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library

if is_empty "${SENTINEL_COMPONENT_NAME}" || is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  if is_empty "${KB_LEAVE_MEMBER_POD_FQDN}" || is_empty "${KB_LEAVE_MEMBER_POD_NAME}"; then
    echo "ERROR: no Sentinel component and leaving-member identity is incomplete — cannot prove memberLeave is safe." >&2
    exit 1
  fi
  build_data_cli "${KB_LEAVE_MEMBER_POD_FQDN}"
  leaving_role=$(run_data_cli INFO replication 2>/dev/null \
                   | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
  echo "Leaving pod: ${KB_LEAVE_MEMBER_POD_FQDN}, role: ${leaving_role:-unknown}"
  if no_sentinel_safety_check "${leaving_role}"; then
    exit 0
  fi
  member_leave_diagnose \
    "no-sentinel-safety-proof" "no" \
    "The leaving pod is not a confirmed replica and no Sentinel topology is configured."
  exit 1
fi

if is_empty "${KB_LEAVE_MEMBER_POD_FQDN}" || is_empty "${KB_LEAVE_MEMBER_POD_NAME}"; then
  member_leave_diagnose \
    "missing-leaving-member" "no" \
    "KB_LEAVE_MEMBER_POD_FQDN and KB_LEAVE_MEMBER_POD_NAME are required to prove memberLeave completion."
  exit 1
fi

if ! canonicalize_sentinel_endpoints "${SENTINEL_POD_FQDN_LIST}"; then
  member_leave_diagnose \
    "invalid-sentinel-endpoints" "no" \
    "SENTINEL_POD_FQDN_LIST must contain unique, nonempty endpoints."
  exit 1
fi

master_name="${VALKEY_COMPONENT_NAME}"
leaving_fqdn="${KB_LEAVE_MEMBER_POD_FQDN}"

# Determine the role of the leaving pod
build_data_cli "${leaving_fqdn}"
leaving_role=$(run_data_cli INFO replication 2>/dev/null \
                 | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true

echo "Leaving pod: ${leaving_fqdn}, role: ${leaving_role:-unknown}"

# Pick one reachable Sentinel only as the command recipient. Completion is
# determined separately by strict-majority readback across every configured
# Sentinel, so this single endpoint can never establish the terminal state.
sentinel_fqdn=""
for s in "${sentinel_fqdns[@]}"; do
  build_sentinel_cli "${s}"
  if timeout "${ACTION_CLIENT_TIMEOUT_SECONDS}" "${_sentinel_cli_cmd[@]}" PING 2>/dev/null | grep -q "PONG"; then
    sentinel_fqdn="${s}"
    break
  fi
done

if is_empty "${sentinel_fqdn}"; then
  if no_sentinel_safety_check "${leaving_role}"; then
    exit 0
  fi
  member_leave_diagnose \
    "sentinel-unreachable" "yes" \
    "No Sentinel answered within ${ACTION_CLIENT_TIMEOUT_SECONDS}s and the leaving pod is not a confirmed replica."
  exit 1
fi

echo "Using sentinel ${sentinel_fqdn} as the failover command recipient"
build_sentinel_cli "${sentinel_fqdn}"
s_cli=("${_sentinel_cli_cmd[@]}")

# Resolve the leaving pod's IP once for all comparisons below.
leaving_ip=$(timeout "${ACTION_CLIENT_TIMEOUT_SECONDS}" getent hosts "${leaving_fqdn}" 2>/dev/null \
  | awk '{print $1}' | head -n1) || true

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
#       call FAILOVER and return a classified retry. A later invocation only
#       succeeds after Sentinel positively reports a different master.
#   - leaving_role == "master" AND sentinel already moved on (fast-path):
#       skip FAILOVER. KubeBlocks removes the pod next; sentinel naturally
#       marks it s_down and excludes it from decisions.
#   - leaving_role == "slave" (non-master):
#       no sentinel action needed. Sentinel self-cleans once the pod is gone.

case "${leaving_role}" in
  slave)
    echo "Leaving pod is a confirmed replica — memberLeave is safe to continue."
    ;;
  master)
    handle_master_leave || exit 1
    ;;
  *)
    member_leave_diagnose \
      "leaving-role-unknown" "yes" \
      "The leaving pod did not return role:master or role:slave within ${ACTION_CLIENT_TIMEOUT_SECONDS}s."
    exit 1
    ;;
esac

echo "Member leave handling positively confirmed."
