#!/bin/bash
# switchover.sh — graceful primary promotion for the replication topology.
#
# The flow mirrors the redis addon's redis-switchover.sh:
#   1. pre-checks   — only for KB_SWITCHOVER_ROLE=primary, at least 2 replicas,
#                     Sentinel present, candidate (if any) currently a slave;
#   2. bias         — remember every pod's replica-priority, then set the
#                     requested candidate to 1 and the other replicas to 100;
#   3. failover     — `SENTINEL FAILOVER <master-name>` on the first Sentinel
#                     that accepts it;
#   4. verification — poll the DATA PLANE (INFO replication on every pod) until
#                     the requested candidate reports role:master (or, when no
#                     candidate was requested, until somebody else is master);
#   5. restore      — put the remembered replica-priorities back.
#
# KubeBlocks injects before calling switchover:
#   KB_SWITCHOVER_ROLE            - "primary"
#   KB_SWITCHOVER_CURRENT_NAME    - pod name of the current primary
#   KB_SWITCHOVER_CURRENT_FQDN    - FQDN of the current primary
#   KB_SWITCHOVER_CANDIDATE_NAME  - target pod name (empty = "any replica")
#   KB_SWITCHOVER_CANDIDATE_FQDN  - FQDN of the target (empty = "any replica")
#
# Why the result is verified on the data plane and never through the Sentinel
# replica cache: in advertised-address topologies (NodePort / LoadBalancer) a
# Sentinel lists its replicas as "<node-ip>:<nodeport>", not as pod FQDNs, so
# any check that matches a replica by pod name can never confirm.  The pods
# themselves answer `INFO replication` over the very connection the switchover
# is supposed to produce, which makes them the authority here (redis parity).
#
# Deliberate deltas vs the redis addon, kept because they are safety fixes:
#   * a never-promote replica (replica-priority 0) is left at 0 instead of
#     being normalised to 100 — the candidate at 1 still outranks it, and 0
#     can never be promoted if the candidate dies mid-failover (#3016);
#   * the remembered priorities are restored on the FAILURE paths too, so a
#     failed switchover never leaves a replica biased to priority 1;
#   * an unreachable candidate aborts instead of proceeding with a blind bias;
#   * a candidate that is already master is an idempotent success;
#   * a candidate missing from a stale VALKEY_POD_FQDN_LIST (scale-out) is
#     appended, so it is still biased and verified.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${SERVICE_PORT:-6379}"

# replica-priority values used for the bias window (Sentinel promotes the
# replica with the LOWEST non-zero priority).
_candidate_priority=1
_other_priority=100

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

build_cli() {
  local host="${1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    _cli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

sentinel_cli_for() {
  local host="${1}"
  # Resolved per call: the Sentinel port is injected at action time.
  local s_port="${SENTINEL_SERVICE_PORT:-26379}"
  _sentinel_cli=(valkey-cli --no-auth-warning -h "${host}" -p "${s_port}")
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    _sentinel_cli+=(-a "${SENTINEL_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    _sentinel_cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# ── environment / role helpers ───────────────────────────────────────────────

# check_environment_exist — the action is a no-op for a single-replica
# component (there is nothing to fail over to) and for any role but primary.
check_environment_exist() {
  if ! is_empty "${COMPONENT_REPLICAS}" && [ "${COMPONENT_REPLICAS}" -lt 2 ]; then
    echo "component has ${COMPONENT_REPLICAS} replica(s) — nothing to switch over, exiting."
    exit 0
  fi
  if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
    echo "switchover not for primary role (got '${KB_SWITCHOVER_ROLE}') — exiting."
    exit 0
  fi
}

# valkey_role <fqdn> — "master" / "slave" from the pod itself, empty when the
# pod cannot be reached or has not answered yet.
valkey_role() {
  local fqdn="${1}"
  build_cli "${fqdn}"
  "${_cli[@]}" info replication 2>/dev/null | grep "^role:" | tr -d '\r\n' | cut -d: -f2
}

# valkey_kernel_status — scan every pod and print the FQDN of the single
# master.  Fails when there is no master or more than one (split brain).
valkey_kernel_status() {
  local -a pod_fqdns=()
  local fqdn role master="" unreachable=0
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for fqdn in "${pod_fqdns[@]}"; do
    [ -n "${fqdn}" ] || continue
    role=$(valkey_role "${fqdn}") || true
    if is_empty "${role}"; then
      unreachable=$((unreachable + 1))
      continue
    fi
    if [ "${role}" = "master" ]; then
      if ! is_empty "${master}"; then
        echo "ERROR: multiple primaries detected: ${master} and ${fqdn}" >&2
        return 1
      fi
      master="${fqdn}"
    fi
  done
  if is_empty "${master}"; then
    echo "ERROR: no primary found (${unreachable} pod(s) unreachable)" >&2
    return 1
  fi
  echo "${master}"
}

# pod_fqdns_with_candidate <candidate_fqdn> — VALKEY_POD_FQDN_LIST is rendered
# into the pod environment at pod creation time, so after a scale-out the old
# pods still carry a list without the fresh candidate.  KB_SWITCHOVER_*_FQDN is
# injected at action time, so append it when it is missing.
pod_fqdns_with_candidate() {
  local candidate_fqdn="${1}"
  local result="${VALKEY_POD_FQDN_LIST:-}"
  if is_empty "${candidate_fqdn}"; then
    echo "${result}"
    return 0
  fi

  local candidate_pod="${candidate_fqdn%%.*}"
  local fqdn
  IFS=',' read -ra pod_fqdns <<< "${result}"
  for fqdn in "${pod_fqdns[@]}"; do
    [ "${fqdn%%.*}" = "${candidate_pod}" ] && echo "${result}" && return 0
  done

  if is_empty "${result}"; then
    echo "${candidate_fqdn}"
  else
    echo "${result},${candidate_fqdn}"
  fi
}

# ── replica-priority bias ────────────────────────────────────────────────────

_orig_prio_fqdns=()
_orig_prio_values=()

# get_replica_priority <fqdn> — current replica-priority of that pod.
get_replica_priority() {
  local fqdn="${1}"
  build_cli "${fqdn}"
  "${_cli[@]}" CONFIG GET replica-priority 2>/dev/null | tail -1 | tr -d '\r\n'
}

# _do_set_replica_priority <fqdn> <prio> — CONFIG SET with an explicit answer
# check (valkey-cli exits 0 even for protocol errors).
_do_set_replica_priority() {
  local fqdn="${1}" prio="${2}"
  local output
  build_cli "${fqdn}"
  output=$("${_cli[@]}" CONFIG SET replica-priority "${prio}" 2>/dev/null) || true
  output="${output//$'\r'/}"
  if [ "${output}" = "OK" ]; then
    return 0
  fi
  echo "WARNING: CONFIG SET replica-priority ${prio} on ${fqdn} returned: ${output:-<empty>}" >&2
  return 1
}

set_replica_priority() {
  local fqdn="${1}" prio="${2}"
  call_func_with_retry 3 3 _do_set_replica_priority "${fqdn}" "${prio}"
}

# capture_replica_priorities <csv fqdns> — record what every pod has before the
# bias is applied, so the restore step puts back user-configured values instead
# of a hardcoded 100 (replica-priority is a user-settable dynamic parameter).
capture_replica_priorities() {
  local all_fqdns_csv="${1}"
  local -a all_fqdns=()
  local fqdn prio
  IFS=',' read -ra all_fqdns <<< "${all_fqdns_csv}"
  _orig_prio_fqdns=()
  _orig_prio_values=()
  for fqdn in "${all_fqdns[@]}"; do
    [ -n "${fqdn}" ] || continue
    prio=$(get_replica_priority "${fqdn}") || true
    # A pod that cannot be reached is recorded as the default so a later
    # restore never writes an empty value into CONFIG SET.
    is_empty "${prio}" && prio="100"
    _orig_prio_fqdns+=("${fqdn}")
    _orig_prio_values+=("${prio}")
  done
}

# captured_replica_priority <fqdn> — pre-bias value, "100" when unknown.
captured_replica_priority() {
  local fqdn="${1}"
  local i
  for i in "${!_orig_prio_fqdns[@]}"; do
    if [ "${_orig_prio_fqdns[$i]}" = "${fqdn}" ]; then
      echo "${_orig_prio_values[$i]}"
      return 0
    fi
  done
  echo "100"
}

# restore_replica_priorities — put back every captured value.  Called on the
# success path AND on every failure path, so a failed switchover never leaves a
# replica biased to priority 1 (which would make Sentinel promote it later).
restore_replica_priorities() {
  local i
  if [ "${#_orig_prio_fqdns[@]}" -eq 0 ]; then
    return 0
  fi
  echo "Restoring replica-priorities..."
  for i in "${!_orig_prio_fqdns[@]}"; do
    set_replica_priority "${_orig_prio_fqdns[$i]}" "${_orig_prio_values[$i]}" || \
      echo "WARNING: failed to restore replica-priority on ${_orig_prio_fqdns[$i]}" >&2
  done
}

# bias_replica_priorities <candidate_fqdn> <csv fqdns> — candidate to 1, every
# other promotable replica to 100.  Returns non-zero when a CONFIG SET failed.
bias_replica_priorities() {
  local candidate_fqdn="${1}" all_fqdns_csv="${2}"
  local -a all_fqdns=()
  local fqdn failed=0
  IFS=',' read -ra all_fqdns <<< "${all_fqdns_csv}"
  for fqdn in "${all_fqdns[@]}"; do
    [ -n "${fqdn}" ] || continue
    # Append "." so "valkey-1." cannot match "valkey-11.headless..." .
    if contains "${fqdn}" "${candidate_fqdn%%.*}."; then
      if [ "$(captured_replica_priority "${fqdn}")" = "0" ]; then
        echo "WARNING: candidate ${fqdn} has replica-priority=0 (never-promote); an explicit targeted switchover overrides it for this operation." >&2
      fi
      set_replica_priority "${fqdn}" "${_candidate_priority}" || failed=1
    else
      # 0 means never promote: leave it untouched (see the header note).
      if [ "$(captured_replica_priority "${fqdn}")" = "0" ]; then
        echo "Preserving never-promote replica-priority=0 on ${fqdn} (bias skipped)."
        continue
      fi
      set_replica_priority "${fqdn}" "${_other_priority}" || failed=1
    fi
  done
  if [ "${failed}" -ne 0 ]; then
    echo "ERROR: failed to apply the replica-priority bias — aborting switchover" >&2
    return 1
  fi
}

# ── Sentinel failover ────────────────────────────────────────────────────────

execute_sentinel_failover() {
  local master_name="${1:-${VALKEY_COMPONENT_NAME}}"
  local -a sentinel_fqdns=()
  local s_fqdn output exit_code
  IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
  for s_fqdn in "${sentinel_fqdns[@]}"; do
    [ -n "${s_fqdn}" ] || continue
    sentinel_cli_for "${s_fqdn}"
    exit_code=0
    output=$("${_sentinel_cli[@]}" SENTINEL FAILOVER "${master_name}" 2>/dev/null) || exit_code=$?
    [ "${exit_code}" -ne 0 ] && continue
    # Strip \r (valkey-cli may return "OK\r" on some platforms, including TLS mode).
    output="${output//$'\r'/}"
    if [ "${output}" = "OK" ]; then
      echo "Sentinel FAILOVER accepted by ${s_fqdn}"
      return 0
    fi
  done
  echo "ERROR: all Sentinel FAILOVER attempts failed" >&2
  return 1
}

# ── data-plane verification ──────────────────────────────────────────────────

# check_switchover_result <expected_fqdn> <initial_master_fqdn>
# Polls the pods until the requested candidate reports role:master.  Without a
# candidate, any master other than the initial one counts.  The old master is
# skipped while it is still stepping down, so a stale role:master answer from it
# is never mistaken for the new topology.
check_switchover_result() {
  local expected_fqdn="${1}" initial_master="${2}"
  local max_wait=300 wait_interval=5 elapsed=0
  local current_master=""
  local candidate_pod="${expected_fqdn%%.*}"
  local initial_pod="${initial_master%%.*}"

  while [ "${elapsed}" -lt "${max_wait}" ]; do
    IFS=',' read -ra pod_fqdns <<< "$(pod_fqdns_with_candidate "${expected_fqdn}")"
    current_master=""
    local fqdn role pod
    for fqdn in "${pod_fqdns[@]}"; do
      [ -n "${fqdn}" ] || continue
      role=$(valkey_role "${fqdn}") || true
      [ "${role}" = "master" ] || continue
      pod="${fqdn%%.*}"
      # The old master may still report role:master during stepdown.
      if ! is_empty "${initial_pod}" && [ "${pod}" = "${initial_pod}" ]; then
        continue
      fi
      current_master="${fqdn}"
      break
    done

    if ! is_empty "${current_master}"; then
      if ! is_empty "${expected_fqdn}"; then
        if [ "${current_master%%.*}" = "${candidate_pod}" ]; then
          echo "Switchover successful: ${current_master} is now the primary."
          return 0
        fi
        echo "Waiting for ${expected_fqdn} to be promoted (current primary: ${current_master})..."
      else
        echo "Switchover successful: new primary is ${current_master}."
        return 0
      fi
    fi

    sleep_when_ut_mode_false "${wait_interval}"
    elapsed=$((elapsed + wait_interval))
  done

  if ! is_empty "${expected_fqdn}"; then
    echo "ERROR: switchover verification failed — ${expected_fqdn} is not the primary after ${max_wait}s" >&2
  else
    echo "ERROR: switchover verification failed — no new primary after ${max_wait}s" >&2
  fi
  return 1
}

# ── switchover flows ─────────────────────────────────────────────────────────

switchover_with_candidate() {
  local candidate_fqdn="${1}"

  # Pre-check: the candidate must currently be a slave.  An unreachable
  # candidate aborts too — biasing and failing over blind would just waste the
  # whole budget and leave the topology unverified.
  local candidate_role="" _i
  for _i in 1 2 3; do
    candidate_role=$(valkey_role "${candidate_fqdn}") || true
    ! is_empty "${candidate_role}" && break
    sleep_when_ut_mode_false 1
  done
  if is_empty "${candidate_role}"; then
    echo "ERROR: could not determine the role of ${candidate_fqdn} after retries — aborting targeted switchover" >&2
    return 1
  fi
  if [ "${candidate_role}" = "master" ]; then
    # KB can fire a second switchover call after the first succeeded (optimistic
    # lock retry), or an automatic failover already promoted this candidate.
    # The goal state is reached either way, so report success.
    echo "Candidate ${candidate_fqdn} is already the primary — switchover target achieved (idempotent)."
    return 0
  fi
  if [ "${candidate_role}" != "slave" ]; then
    echo "ERROR: candidate ${candidate_fqdn} has role='${candidate_role}', expected 'slave' — aborting switchover" >&2
    return 1
  fi

  local initial_master
  initial_master=$(valkey_kernel_status) || return 1

  local all_fqdns_csv
  all_fqdns_csv="$(pod_fqdns_with_candidate "${candidate_fqdn}")"
  capture_replica_priorities "${all_fqdns_csv}"

  echo "Biasing Sentinel toward candidate ${candidate_fqdn} (candidate=${_candidate_priority}, others=${_other_priority})..."
  if ! bias_replica_priorities "${candidate_fqdn}" "${all_fqdns_csv}"; then
    restore_replica_priorities
    return 1
  fi

  # No Sentinel-side confirmation step: redis addon parity.  Sentinel refreshes
  # its replica cache from the replicas' own INFO, so issuing FAILOVER right
  # after CONFIG SET is what the upstream addon does; the authority for the
  # result is the data plane, checked below.  (A cache-based confirmation could
  # not work in advertised-address topologies anyway: there a Sentinel names its
  # replicas "<node-ip>:<nodeport>", not by pod FQDN.)
  if ! execute_sentinel_failover "${VALKEY_COMPONENT_NAME}"; then
    restore_replica_priorities
    return 1
  fi

  # Restore only AFTER the new primary is confirmed: FAILOVER returning OK means
  # the command was accepted, not that the promotion happened.  Equalising the
  # priorities before the promotion would let Sentinel pick by offset/run_id
  # instead of the requested candidate.
  local rc=0
  check_switchover_result "${candidate_fqdn}" "${initial_master}" || rc=$?
  restore_replica_priorities
  return "${rc}"
}

switchover_without_candidate() {
  local initial_master
  initial_master=$(valkey_kernel_status) || return 1

  if ! execute_sentinel_failover "${VALKEY_COMPONENT_NAME}"; then
    return 1
  fi

  # SENTINEL FAILOVER only means the command was accepted; without this check
  # the OpsRequest would report success even when nobody was promoted.
  check_switchover_result "" "${initial_master}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library

check_environment_exist

if ! is_empty "${SENTINEL_COMPONENT_NAME}" && ! is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  if is_empty "${KB_SWITCHOVER_CANDIDATE_FQDN}"; then
    switchover_without_candidate || exit 1
  else
    switchover_with_candidate "${KB_SWITCHOVER_CANDIDATE_FQDN}" || exit 1
  fi
  echo "Sentinel switchover complete."
  exit 0
fi

# No Sentinel: there is no HA coordinator that can prove the new primary and
# the replica routing converged, so fail closed instead of promoting blindly.
echo "ERROR: switchover is unsupported without Sentinel; refusing manual best-effort promotion." >&2
exit 1
