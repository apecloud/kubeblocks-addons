#!/bin/bash
# switchover.sh — graceful primary promotion for replication topology.
#
# KubeBlocks injects before calling switchover:
#   KB_SWITCHOVER_ROLE            - "primary"
#   KB_SWITCHOVER_CURRENT_NAME    - pod name of the current primary
#   KB_SWITCHOVER_CURRENT_FQDN   - FQDN of the current primary
#   KB_SWITCHOVER_CANDIDATE_NAME  - target pod name (empty = "any replica")
#   KB_SWITCHOVER_CANDIDATE_FQDN  - FQDN of the target (empty = "any replica")
#
# When Sentinel is present (SENTINEL_COMPONENT_NAME is set):
#   Delegate to "SENTINEL FAILOVER <master-name>".  Sentinel handles everything
#   atomically: it promotes the best replica, repoints all others, and updates
#   its own conf.  If a specific candidate is requested we first set its
#   replica-priority to 1 (highest) so Sentinel picks it.
#
# When Sentinel is absent (standalone replication):
#   Manual approach:
#     1. REPLICAOF NO ONE on the target.
#     2. REPLICAOF <new-primary> on all other pods.

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

build_cli() {
  local host="${1}"
  local cmd="valkey-cli --no-auth-warning -h ${host} -p ${port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  fi
  echo "${cmd}"
}

get_role() {
  local fqdn="${1}"
  local cli
  cli=$(build_cli "${fqdn}")
  ${cli} info replication 2>/dev/null | grep "^role:" | tr -d '\r\n' | cut -d: -f2
}

promote_replica() {
  local target_fqdn="${1}"
  echo "Promoting ${target_fqdn} to primary..."
  local cli output
  cli=$(build_cli "${target_fqdn}")
  # valkey-cli exits 0 even for protocol errors; capture output and check content.
  output=$(${cli} REPLICAOF NO ONE 2>&1) || {
    echo "ERROR: REPLICAOF NO ONE failed on ${target_fqdn}: ${output}" >&2
    return 1
  }
  if [ "${output}" != "OK" ]; then
    echo "ERROR: REPLICAOF NO ONE on ${target_fqdn} returned unexpected response: ${output}" >&2
    return 1
  fi
}

wait_until_master() {
  local fqdn="${1}" max_wait="${2:-10}"
  local elapsed=0
  while [ "${elapsed}" -lt "${max_wait}" ]; do
    local role
    role=$(get_role "${fqdn}") || true
    [ "${role}" = "master" ] && return 0
    sleep_when_ut_mode_false 1
    elapsed=$((elapsed + 1))
  done
  echo "WARNING: ${fqdn} did not confirm master role within ${max_wait}s" >&2
  return 1
}

repoint_one() {
  # Wrapped as a named function so call_func_with_retry can call it by name.
  local fqdn="${1}" new_primary="${2}" target_port="${3}"
  local cli output
  cli=$(build_cli "${fqdn}")
  # valkey-cli exits 0 even for protocol errors; capture output and check content.
  output=$(${cli} REPLICAOF "${new_primary}" "${target_port}" 2>&1) || {
    echo "ERROR: REPLICAOF command failed on ${fqdn}: ${output}" >&2
    return 1
  }
  if [ "${output}" != "OK" ]; then
    echo "ERROR: REPLICAOF ${new_primary}:${target_port} on ${fqdn} returned: ${output}" >&2
    return 1
  fi
}

repoint_replicas() {
  local new_primary_fqdn="${1}"
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for fqdn in "${pod_fqdns[@]}"; do
    [ "${fqdn}" = "${new_primary_fqdn}" ] && continue   # skip the new primary itself
    echo "Repointing ${fqdn} → ${new_primary_fqdn}..."
    call_func_with_retry 3 3 repoint_one "${fqdn}" "${new_primary_fqdn}" "${port}" || \
      echo "WARNING: failed to repoint ${fqdn} to ${new_primary_fqdn} — it may remain pointing at the old primary" >&2
  done
}

pick_any_secondary() {
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for fqdn in "${pod_fqdns[@]}"; do
    [ "${fqdn}" = "${KB_SWITCHOVER_CURRENT_FQDN}" ] && continue
    local role
    role=$(get_role "${fqdn}") || continue
    if [ "${role}" = "slave" ]; then
      echo "${fqdn}"
      return 0
    fi
  done
  echo ""
}

# ── Sentinel-based switchover ────────────────────────────────────────────────

sentinel_cli_for() {
  local host="${1}"
  local s_port="${SENTINEL_SERVICE_PORT:-26379}"
  local cmd="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h ${host} -p ${s_port}"
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    cmd="${cmd} -a ${SENTINEL_PASSWORD}"
  fi
  echo "${cmd}"
}

_do_set_replica_priority() {
  local fqdn="${1}" prio="${2}"
  local cli output
  cli=$(build_cli "${fqdn}")
  # Capture only stdout (the Valkey protocol response); redirect stderr to
  # /dev/null so TLS warnings do not pollute the comparison value.
  # valkey-cli exits 0 even for protocol errors, so we check output content.
  output=$(${cli} CONFIG SET replica-priority "${prio}" 2>/dev/null) || true
  # Strip \r (valkey-cli may return "OK\r" on some platforms).
  output="${output//$'\r'/}"
  if [ "${output}" = "OK" ]; then
    return 0
  fi
  echo "WARNING: CONFIG SET replica-priority ${prio} on ${fqdn} returned: ${output}" >&2
  return 1
}

set_replica_priority() {
  local fqdn="${1}" prio="${2}"
  call_func_with_retry 3 3 _do_set_replica_priority "${fqdn}" "${prio}"
}

execute_sentinel_failover() {
  local master_name="${VALKEY_COMPONENT_NAME}"
  IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
  for s_fqdn in "${sentinel_fqdns[@]}"; do
    local cli output
    cli=$(sentinel_cli_for "${s_fqdn}")
    local exit_code=0
    output=$(${cli} SENTINEL FAILOVER "${master_name}" 2>/dev/null) || exit_code=$?
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

wait_sentinel_sees_priority() {
  # Poll until ALL Sentinels report that the candidate replica's slave-priority
  # matches expected_prio, or until the deadline is reached.
  #
  # Why ALL Sentinels: CONFIG SET replica-priority propagates into each
  # Sentinel's replica cache independently (~10s refresh cycle per Sentinel).
  # If we return as soon as ANY Sentinel confirms (first-match), the Sentinel
  # that receives the FAILOVER command may still have a stale cache and pick the
  # wrong replica.  Requiring ALL Sentinels to confirm ensures that whichever
  # Sentinel is chosen by execute_sentinel_failover has up-to-date priority data.
  local candidate_fqdn="${1}" expected_prio="${2}"
  local candidate_host="${candidate_fqdn%%.*}"   # e.g. "valkey-1"
  # 30s covers 3 Sentinel info-refresh cycles (~10s each), giving ample time for
  # CONFIG SET replica-priority to propagate into every Sentinel's replica cache.
  local deadline=$((SECONDS + 30))

  while [ "${SECONDS}" -lt "${deadline}" ]; do
    IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
    local confirmed=0 total=${#sentinel_fqdns[@]}
    for s_fqdn in "${sentinel_fqdns[@]}"; do
      local cli prio
      cli=$(sentinel_cli_for "${s_fqdn}")
      # Parse SENTINEL REPLICAS output:
      #   tr -d '"'       — strip valkey-cli string quotes
      #   sed 's/.*) //'  — strip leading array-index prefixes like "  3) "
      #   awk             — find the replica matching candidate_host, extract slave-priority
      #                     Uses index()+literal "." suffix (e.g. "valkey-1.")
      #                     to avoid "valkey-1" substring-matching "valkey-10".
      prio=$(${cli} SENTINEL REPLICAS "${VALKEY_COMPONENT_NAME}" 2>/dev/null \
        | tr -d '"' \
        | sed 's/.*) //' \
        | awk -v cand="${candidate_host}." '
            prev == "name" { in_cand = (index($0, cand) > 0) }
            in_cand && prev == "slave-priority" { print; exit }
            { prev = $0 }
          ') || true
      if [ "${prio}" = "${expected_prio}" ]; then
        confirmed=$((confirmed + 1))
      fi
    done
    if [ "${confirmed}" -eq "${total}" ]; then
      echo "All ${total} Sentinel(s) confirmed: ${candidate_fqdn} slave-priority=${expected_prio}."
      return 0
    fi
    sleep_when_ut_mode_false 1
  done
  # Abort rather than proceed: if not all Sentinels have the updated priority
  # after 30s, issuing SENTINEL FAILOVER now risks promoting the wrong replica.
  # Returning 1 causes the targeted switchover to fail fast so the caller can retry.
  echo "ERROR: Sentinel did not reflect priority=${expected_prio} for ${candidate_fqdn} within 30s — aborting targeted switchover" >&2
  return 1
}

wait_for_new_master() {
  local expected_fqdn="${1}"   # may be empty (no candidate specified)
  local exclude_fqdn="${2}"    # old master FQDN to skip (avoids returning on old master during stepdown)
  local max_wait=300 elapsed=0

  while [ "${elapsed}" -lt "${max_wait}" ]; do
    IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
    for fqdn in "${pod_fqdns[@]}"; do
      local role
      role=$(get_role "${fqdn}") || continue
      if [ "${role}" = "master" ]; then
        # Skip the old master — it may still report role=master during stepdown.
        if ! is_empty "${exclude_fqdn}" && contains "${fqdn}" "${exclude_fqdn%%.*}."; then
          continue
        fi
        # Compare pod-name segments exactly to avoid "pod-1" matching "pod-10".
        local fqdn_pod expected_pod
        fqdn_pod="${fqdn%%.*}"
        expected_pod="${expected_fqdn%%.*}"
        if is_empty "${expected_fqdn}" || [ "${fqdn_pod}" = "${expected_pod}" ]; then
          echo "New primary confirmed: ${fqdn}"
          return 0
        fi
      fi
    done
    sleep_when_ut_mode_false 3
    elapsed=$((elapsed + 3))
  done
  echo "WARNING: could not confirm new primary within ${max_wait}s" >&2
  return 1
}

switchover_with_sentinel() {
  local candidate_fqdn="${1}"   # may be empty

  if ! is_empty "${candidate_fqdn}"; then
    # Pre-check: candidate must currently be a slave.
    # If we can determine its role and it is NOT slave, abort immediately —
    # Sentinel cannot promote a non-slave and we would just spin until timeout.
    # If the role is unknown (pod unreachable), log a warning and continue;
    # the priority-setting retry loop will surface the connectivity problem.
    local candidate_role=""
    local _i
    for _i in 1 2 3; do
      candidate_role=$(get_role "${candidate_fqdn}") || true
      ! is_empty "${candidate_role}" && break
      sleep_when_ut_mode_false 1
    done
    if ! is_empty "${candidate_role}" && [ "${candidate_role}" = "master" ]; then
      # Candidate is already master — switchover target achieved.
      # This happens when KB reconcile fires a second switchover call after the
      # first already succeeded (optimistic-lock retry), or when a prior automatic
      # failover already promoted this candidate.  In both cases the goal state
      # is reached: the specified candidate is master.  Return success (idempotent).
      echo "Candidate ${candidate_fqdn} already master — switchover target achieved, returning success (idempotent)." >&2
      return 0
    elif ! is_empty "${candidate_role}" && [ "${candidate_role}" != "slave" ]; then
      echo "ERROR: candidate ${candidate_fqdn} has role='${candidate_role}', expected 'slave' — aborting switchover" >&2
      return 1
    elif is_empty "${candidate_role}"; then
      echo "WARNING: could not determine role of ${candidate_fqdn} after retries — proceeding without role pre-check" >&2
    fi

    echo "Biasing Sentinel toward candidate ${candidate_fqdn}..."
    # Set candidate priority to 1 (best), all others to 100 (lowest).
    # If priority cannot be set (e.g. transient TLS connection failure), log a
    # warning and continue without bias — Sentinel will still elect a new primary.
    IFS=',' read -ra all_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
    for fqdn in "${all_fqdns[@]}"; do
      # Append "." so "valkey-1." is not a substring of "valkey-11.headless..." (substring false positive).
      if contains "${fqdn}" "${candidate_fqdn%%.*}."; then
        if ! set_replica_priority "${fqdn}" 1; then
          echo "WARNING: failed to set priority on candidate ${fqdn} — proceeding without priority bias" >&2
          # Do not abort: let Sentinel proceed and pick whichever candidate it prefers.
        fi
      else
        set_replica_priority "${fqdn}" 100 || true
      fi
    done

    # Wait for Sentinel's replica-info cache to reflect the new priority before
    # issuing FAILOVER.  Sentinel refreshes its replica cache every ~10 seconds;
    # without this wait, FAILOVER may be issued while the cache still shows the
    # old priority=100, causing Sentinel to pick the wrong replica.
    echo "Waiting for Sentinel to reflect priority bias on ${candidate_fqdn}..."
    if ! wait_sentinel_sees_priority "${candidate_fqdn}" "1"; then
      # Sentinel did not reflect the priority in time — restore before aborting
      # so the bias is never left in place after a failed switchover attempt.
      IFS=',' read -ra all_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
      for fqdn in "${all_fqdns[@]}"; do
        set_replica_priority "${fqdn}" 100 || true
      done
      return 1
    fi
  fi

  if ! execute_sentinel_failover; then
    # Restore priorities before failing so future Sentinel failovers are not biased.
    if ! is_empty "${candidate_fqdn}"; then
      IFS=',' read -ra all_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
      for fqdn in "${all_fqdns[@]}"; do
        set_replica_priority "${fqdn}" 100 || true
      done
    fi
    return 1
  fi
  if ! is_empty "${candidate_fqdn}"; then
    # Defer priority restoration until AFTER wait_for_new_master completes.
    # execute_sentinel_failover returning OK only means Sentinel accepted the
    # command; Sentinel selects the slave asynchronously (~1s window).  Restoring
    # priority=100 before +selected-slave would equalise valkey-1 and valkey-2,
    # letting Sentinel pick by offset/run_id instead of the intended candidate.
    local wfnm_rc=0
    wait_for_new_master "${candidate_fqdn}" "${KB_SWITCHOVER_CURRENT_FQDN}" || wfnm_rc=$?
    # Restore priorities on both success and failure paths — Sentinel has now
    # committed +switch-master (or timed out), so the bias is no longer needed.
    IFS=',' read -ra all_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
    for fqdn in "${all_fqdns[@]}"; do
      set_replica_priority "${fqdn}" 100 || true
    done
    return "${wfnm_rc}"
  else
    # No candidate: any new master is a valid outcome — best-effort wait only.
    wait_for_new_master "" "${KB_SWITCHOVER_CURRENT_FQDN}" || true
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────────
load_common_library

# Nothing to do for single-replica clusters
if [ "${COMPONENT_REPLICAS}" -lt 2 ]; then
  echo "Only one replica — nothing to switch over."
  exit 0
fi

# Only act when KubeBlocks asks us to transfer the primary role
if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
  echo "switchover not for primary role (got '${KB_SWITCHOVER_ROLE}') — exiting."
  exit 0
fi

# ── Sentinel path ──
if ! is_empty "${SENTINEL_COMPONENT_NAME}" && ! is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  echo "Sentinel detected — delegating failover to Sentinel."
  switchover_with_sentinel "${KB_SWITCHOVER_CANDIDATE_FQDN}" || exit 1
  echo "Sentinel switchover complete."
  exit 0
fi

# ── Manual path (no Sentinel) ──
target_fqdn="${KB_SWITCHOVER_CANDIDATE_FQDN}"
if is_empty "${target_fqdn}"; then
  target_fqdn=$(pick_any_secondary)
  if is_empty "${target_fqdn}"; then
    echo "ERROR: no available secondary found" >&2
    exit 1
  fi
fi

echo "Manual switchover: ${KB_SWITCHOVER_CURRENT_FQDN} → ${target_fqdn}"

promote_replica "${target_fqdn}"
# wait_until_master is best-effort: repoint_replicas must always run even on
# timeout to avoid leaving replicas pointed at the old (demoted) primary.
wait_until_master "${target_fqdn}" 10 || true
repoint_replicas "${target_fqdn}"

echo "Manual switchover complete. New primary: ${target_fqdn}"
