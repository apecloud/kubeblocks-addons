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
    local candidate_role
    candidate_role=$(get_role "${candidate_fqdn}") || true
    if [ "${candidate_role}" != "slave" ]; then
      echo "ERROR: candidate ${candidate_fqdn} has role='${candidate_role:-<unknown>}', expected 'slave' — aborting switchover" >&2
      return 1
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
    # Restore priorities before the confirmation check so they are never left
    # biased even if we return failure below.
    IFS=',' read -ra all_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
    for fqdn in "${all_fqdns[@]}"; do
      set_replica_priority "${fqdn}" 100 || true
    done
    # Targeted switchover: confirm the requested candidate actually became master.
    # Returning 1 here lets KubeBlocks report the OpsRequest as Failed rather than
    # waiting silently until its own timeout with the wrong pod as master.
    wait_for_new_master "${candidate_fqdn}" "${KB_SWITCHOVER_CURRENT_FQDN}" || return 1
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
