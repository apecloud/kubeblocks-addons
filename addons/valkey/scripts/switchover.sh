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
# When Sentinel is absent:
#   Fail closed. Valkey standalone/no-Sentinel topology has no HA coordinator
#   that can prove the new primary and replica routing converged.

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

get_role() {
  local fqdn="${1}"
  build_cli "${fqdn}"
  "${_cli[@]}" info replication 2>/dev/null | grep "^role:" | tr -d '\r\n' | cut -d: -f2
}

read_action_candidate_announced_endpoint() {
  local fqdn="${1}" host_output port_output
  local host_key host_value host_extra port_key port_value port_extra
  build_cli "${fqdn}"
  host_output=$("${_cli[@]}" CONFIG GET replica-announce-ip 2>/dev/null) || return 1
  port_output=$("${_cli[@]}" CONFIG GET replica-announce-port 2>/dev/null) || return 1
  host_output="${host_output//$'\r'/}"
  port_output="${port_output//$'\r'/}"
  host_key=$(printf '%s\n' "${host_output}" | sed -n '1p')
  host_value=$(printf '%s\n' "${host_output}" | sed -n '2p')
  host_extra=$(printf '%s\n' "${host_output}" | sed -n '3p')
  port_key=$(printf '%s\n' "${port_output}" | sed -n '1p')
  port_value=$(printf '%s\n' "${port_output}" | sed -n '2p')
  port_extra=$(printf '%s\n' "${port_output}" | sed -n '3p')
  [ "${host_key}" = "replica-announce-ip" ] && [ -n "${host_value}" ] &&
    [ -z "${host_extra}" ] || return 1
  [ "${port_key}" = "replica-announce-port" ] && [ -n "${port_value}" ] &&
    [ -z "${port_extra}" ] || return 1
  case "${port_value}" in
    *[!0-9]*) return 1 ;;
  esac
  printf '%s\n%s\n' "${host_value}" "${port_value}"
}

pod_fqdns_with_candidate() {
  # VALKEY_POD_FQDN_LIST is rendered into pod environment at pod creation time.
  # After scale-out, old primary pods can still have a stale list that does not
  # include the fresh candidate. KB_SWITCHOVER_CANDIDATE_FQDN is injected at
  # action time, so append it here for targeted switchover bookkeeping.
  local candidate_fqdn="${1}"
  local result="${VALKEY_POD_FQDN_LIST:-}"
  if is_empty "${candidate_fqdn}"; then
    echo "${result}"
    return 0
  fi

  local candidate_pod="${candidate_fqdn%%.*}"
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

# ── Sentinel-based switchover ────────────────────────────────────────────────

sentinel_cli_for() {
  local host="${1}"
  local s_port="${SENTINEL_SERVICE_PORT:-26379}"
  # shellcheck disable=SC2206
  _sentinel_cli=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h "${host}" -p "${s_port}")
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    _sentinel_cli+=(-a "${SENTINEL_PASSWORD}")
  fi
}

_do_set_replica_priority() {
  local fqdn="${1}" prio="${2}"
  local output
  build_cli "${fqdn}"
  # Capture only stdout (the Valkey protocol response); redirect stderr to
  # /dev/null so TLS warnings do not pollute the comparison value.
  # valkey-cli exits 0 even for protocol errors, so we check output content.
  output=$("${_cli[@]}" CONFIG SET replica-priority "${prio}" 2>/dev/null) || true
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

get_replica_priority() {
  local fqdn="${1}"
  build_cli "${fqdn}"
  "${_cli[@]}" CONFIG GET replica-priority 2>/dev/null | tail -1 | tr -d '\r\n'
}

# capture_replica_priorities — record each pod's current replica-priority
# before the targeted-switchover bias is applied, so the restore step can
# put back the user-configured values instead of blindly writing 100
# (replica-priority is a user-settable dynamic parameter; clobbering it
# silently drifts the runtime away from the declared desired config).
# Unreachable pods default to 100 (the engine default).
capture_replica_priorities() {
  local all_fqdns_csv="${1}"
  _orig_prio_fqdns=()
  _orig_prio_values=()
  local _cap_fqdns=() fqdn prio
  IFS=',' read -ra _cap_fqdns <<< "${all_fqdns_csv}"
  for fqdn in "${_cap_fqdns[@]}"; do
    prio=$(get_replica_priority "${fqdn}") || true
    case "${prio}" in
      ''|*[!0-9]*) prio="100" ;;
    esac
    _orig_prio_fqdns+=("${fqdn}")
    _orig_prio_values+=("${prio}")
  done
}

restore_replica_priorities() {
  local i
  for i in "${!_orig_prio_fqdns[@]}"; do
    set_replica_priority "${_orig_prio_fqdns[$i]}" "${_orig_prio_values[$i]}" || true
  done
}

# captured_replica_priority — look up the pre-bias value recorded by
# capture_replica_priorities. Prints the captured value, or 100 when the
# fqdn was never captured (defensive default, same as capture's fallback).
captured_replica_priority() {
  local fqdn="${1}" i
  for i in "${!_orig_prio_fqdns[@]}"; do
    if [ "${_orig_prio_fqdns[$i]}" = "${fqdn}" ]; then
      echo "${_orig_prio_values[$i]}"
      return 0
    fi
  done
  echo "100"
}

sentinel_observed_replica_priority() {
  local sentinel_fqdn="${1}" replica_fqdn="${2}"
  local replica_host="${replica_fqdn%%.*}"
  sentinel_cli_for "${sentinel_fqdn}"
  "${_sentinel_cli[@]}" SENTINEL REPLICAS "${VALKEY_COMPONENT_NAME}" 2>/dev/null \
    | tr -d '"' \
    | sed 's/.*) //' \
    | awk -v cand="${replica_host}." '
        prev == "name" { in_cand = (index($0, cand) > 0) }
        in_cand && prev == "slave-priority" { print; exit }
        { prev = $0 }
      '
}

execute_sentinel_failover() {
  local master_name="${VALKEY_COMPONENT_NAME}"
  local sentinel_endpoints s_fqdn
  sentinel_endpoints=$(canonical_sentinel_fqdns) || return 1
  while IFS= read -r s_fqdn; do
    [ -z "${s_fqdn}" ] && continue
    local output exit_code=0
    sentinel_cli_for "${s_fqdn}"
    output=$("${_sentinel_cli[@]}" SENTINEL FAILOVER "${master_name}" 2>/dev/null) || exit_code=$?
    [ "${exit_code}" -ne 0 ] && continue
    # Strip \r (valkey-cli may return "OK\r" on some platforms, including TLS mode).
    output="${output//$'\r'/}"
    if [ "${output}" = "OK" ]; then
      echo "Sentinel FAILOVER accepted by ${s_fqdn}"
      return 0
    fi
  done <<< "${sentinel_endpoints}"
  echo "ERROR: all Sentinel FAILOVER attempts failed" >&2
  return 1
}

canonical_sentinel_fqdns() {
  local raw fqdn seen existing
  local unique=()
  IFS=',' read -ra raw <<< "${SENTINEL_POD_FQDN_LIST:-}"
  for fqdn in "${raw[@]}"; do
    [ -z "${fqdn}" ] && continue
    seen=0
    for existing in "${unique[@]}"; do
      [ "${existing}" = "${fqdn}" ] && seen=1 && break
    done
    if [ "${seen}" -eq 1 ]; then
      echo "ERROR: duplicate Sentinel endpoint in SENTINEL_POD_FQDN_LIST: ${fqdn}" >&2
      return 1
    fi
    unique+=("${fqdn}")
  done
  [ "${#unique[@]}" -gt 0 ] || {
    echo "ERROR: SENTINEL_POD_FQDN_LIST has no usable endpoints" >&2
    return 1
  }
  printf '%s\n' "${unique[@]}"
}

# Resolve the current master only from a strict majority of the configured,
# unique Sentinel endpoints. Reachable-only quorum is not authoritative.
sentinel_master_host() {
  local endpoints fqdn output host reported_port canonical_host i found winner="" winner_count=0
  local hosts=() counts=()
  endpoints=$(canonical_sentinel_fqdns) || return 1
  local configured_count
  configured_count=$(printf '%s\n' "${endpoints}" | grep -c .)
  local min_valid=$((configured_count / 2 + 1))
  while IFS= read -r fqdn; do
    [ -z "${fqdn}" ] && continue
    sentinel_cli_for "${fqdn}"
    output=$("${_sentinel_cli[@]}" SENTINEL GET-MASTER-ADDR-BY-NAME "${VALKEY_COMPONENT_NAME}" 2>/dev/null | tr -d '\r') || continue
    host=$(printf '%s\n' "${output}" | sed -n '1p')
    reported_port=$(printf '%s\n' "${output}" | sed -n '2p')
    canonical_host=$(resolve_sentinel_master_endpoint "${host}" "${reported_port}") || continue
    found=0
    for i in "${!hosts[@]}"; do
      if [ "${hosts[$i]}" = "${canonical_host}" ]; then
        counts[$i]=$((counts[$i] + 1))
        found=1
        break
      fi
    done
    if [ "${found}" -eq 0 ]; then
      hosts+=("${canonical_host}")
      counts+=(1)
    fi
  done <<< "${endpoints}"
  for i in "${!hosts[@]}"; do
    if [ "${counts[$i]}" -gt "${winner_count}" ]; then
      winner="${hosts[$i]}"
      winner_count="${counts[$i]}"
    fi
  done
  [ "${winner_count}" -ge "${min_valid}" ] || {
    echo "ERROR: Sentinel master view has no configured-endpoint majority (${winner_count}/${configured_count}, need ${min_valid})" >&2
    return 1
  }
  printf '%s\n' "${winner}"
}

same_pod_identity() {
  [ "${1%%.*}" = "${2%%.*}" ]
}

sentinel_switchover_converged() {
  local expected_fqdn="${1}" old_fqdn="${2}" master_host candidate_role old_role
  master_host=$(sentinel_master_host) || return 1
  if [ -n "${expected_fqdn}" ] && ! same_pod_identity "${master_host}" "${expected_fqdn}"; then
    return 1
  fi
  same_pod_identity "${master_host}" "${old_fqdn}" && return 1
  candidate_role=$(get_role "${master_host}") || return 1
  old_role=$(get_role "${old_fqdn}") || return 1
  [ "${candidate_role}" = "master" ] && [ "${old_role}" = "slave" ] || return 1
  SENTINEL_CONFIRMED_MASTER="${master_host}"
  return 0
}

wait_sentinel_sees_priority_bias() {
  # Poll until ALL Sentinels report the full priority bias (candidate=1,
  # everyone else=100), or until the deadline is reached.
  #
  # Why ALL Sentinels: CONFIG SET replica-priority propagates into each
  # Sentinel's replica cache independently (~10s refresh cycle per Sentinel).
  # If we return as soon as ANY Sentinel confirms (first-match), the Sentinel
  # that receives the FAILOVER command may still have a stale cache and pick the
  # wrong replica.  Requiring ALL Sentinels to confirm ensures that whichever
  # Sentinel is chosen by execute_sentinel_failover has up-to-date priority data.
  # 30s covers 3 Sentinel info-refresh cycles (~10s each).
  local candidate_fqdn="${1}" all_fqdns_csv="${2}"
  local candidate_pod="${candidate_fqdn%%.*}"
  local current_pod="${KB_SWITCHOVER_CURRENT_FQDN%%.*}"
  local confirm_budget="${SENTINEL_PRIORITY_CONFIRM_BUDGET:-20}"
  local deadline=$((SECONDS + confirm_budget))

  while [ "${SECONDS}" -lt "${deadline}" ]; do
    local sentinel_endpoints
    sentinel_endpoints=$(canonical_sentinel_fqdns) || return 1
    IFS=',' read -ra all_fqdns <<< "${all_fqdns_csv}"
    local total=0 confirmed=0
    while IFS= read -r s_fqdn; do
      [ -z "${s_fqdn}" ] && continue
      for fqdn in "${all_fqdns[@]}"; do
        local pod expected_prio observed_prio
        pod="${fqdn%%.*}"
        # The current master is not listed in SENTINEL REPLICAS before failover.
        [ "${pod}" = "${current_pod}" ] && continue
        expected_prio="100"
        # Never-promote replicas keep their captured 0 (bias skipped, #3016).
        [ "$(captured_replica_priority "${fqdn}")" = "0" ] && expected_prio="0"
        [ "${pod}" = "${candidate_pod}" ] && expected_prio="1"
        total=$((total + 1))
        observed_prio=$(sentinel_observed_replica_priority "${s_fqdn}" "${fqdn}") || true
        if [ "${observed_prio}" = "${expected_prio}" ]; then
          confirmed=$((confirmed + 1))
        fi
      done
    done <<< "${sentinel_endpoints}"
    if [ "${total}" -gt 0 ] && [ "${confirmed}" -eq "${total}" ]; then
      echo "All Sentinel replica priority caches confirmed targeted bias for ${candidate_fqdn}."
      return 0
    fi
    sleep_when_ut_mode_false 1
  done

  echo "ERROR: Sentinel did not confirm full targeted priority bias for ${candidate_fqdn} within ${confirm_budget}s — aborting targeted switchover" >&2
  return 1
}

wait_for_new_master() {
  local expected_fqdn="${1}" old_fqdn="${2}"
  local max_wait="${SWITCHOVER_CONFIRM_BUDGET:-15}" elapsed=0

  while [ "${elapsed}" -lt "${max_wait}" ]; do
    if sentinel_switchover_converged "${expected_fqdn}" "${old_fqdn}"; then
      echo "New primary confirmed by Sentinel majority plus data-role readback: ${SENTINEL_CONFIRMED_MASTER}"
      return 0
    fi
    sleep_when_ut_mode_false 3
    elapsed=$((elapsed + 3))
  done
  echo "WARNING: could not confirm new primary within ${max_wait}s" >&2
  return 1
}

switchover_with_sentinel() {
  local candidate_fqdn="${1}"   # may be empty

  canonical_sentinel_fqdns >/dev/null || return 1

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
      if sentinel_switchover_converged "${candidate_fqdn}" "${KB_SWITCHOVER_CURRENT_FQDN}"; then
        echo "Candidate ${candidate_fqdn} already holds the Sentinel-authoritative master role and the old primary is demoted." >&2
        return 0
      fi
      echo "ERROR: candidate ${candidate_fqdn} self-reports master but Sentinel authority and old-primary demotion are not converged" >&2
      return 1
    elif ! is_empty "${candidate_role}" && [ "${candidate_role}" != "slave" ]; then
      echo "ERROR: candidate ${candidate_fqdn} has role='${candidate_role}', expected 'slave' — aborting switchover" >&2
      return 1
    elif is_empty "${candidate_role}"; then
      echo "ERROR: could not determine role of ${candidate_fqdn} after retries — aborting targeted switchover" >&2
      return 1
    fi

    echo "Biasing Sentinel toward candidate ${candidate_fqdn}..."
    IFS=',' read -ra all_fqdns <<< "$(pod_fqdns_with_candidate "${candidate_fqdn}")"
    # Record the current priorities first so every restore path below puts
    # back user-configured values instead of hardcoded 100.
    capture_replica_priorities "$(IFS=','; echo "${all_fqdns[*]}")"
    priority_failed=0
    for fqdn in "${all_fqdns[@]}"; do
      # Append "." so "valkey-1." is not a substring of "valkey-11.headless..." (substring false positive).
      if contains "${fqdn}" "${candidate_fqdn%%.*}."; then
        if [ "$(captured_replica_priority "${fqdn}")" = "0" ]; then
          echo "WARNING: candidate ${fqdn} has replica-priority=0 (never-promote); explicit targeted switchover overrides it for this operation." >&2
        fi
        if ! set_replica_priority "${fqdn}" 1; then
          echo "ERROR: failed to set priority on candidate ${fqdn} — aborting targeted switchover" >&2
          priority_failed=1
        fi
      else
        # replica-priority 0 means NEVER promote (backup/delayed replicas).
        # Biasing it to 100 would make it promotable for the whole window —
        # if the candidate dies mid-failover Sentinel could promote a
        # never-promote replica (issue #3016). Leave 0 untouched: the
        # candidate at priority 1 always outranks any positive priority,
        # and 0 stays out of the election entirely.
        if [ "$(captured_replica_priority "${fqdn}")" = "0" ]; then
          echo "Preserving never-promote replica-priority=0 on ${fqdn} (bias skipped)."
          continue
        fi
        if ! set_replica_priority "${fqdn}" 100; then
          echo "ERROR: failed to normalize priority on ${fqdn} — aborting targeted switchover" >&2
          priority_failed=1
        fi
      fi
    done
    if [ "${priority_failed}" -ne 0 ]; then
      restore_replica_priorities
      return 1
    fi

    # Wait for Sentinel's replica-info cache to reflect the full priority bias before
    # issuing FAILOVER.  Sentinel refreshes its replica cache every ~10 seconds;
    # without this wait, FAILOVER may be issued while another replica still has
    # stale priority=1, causing Sentinel to pick the wrong replica.
    echo "Waiting for Sentinel to reflect full priority bias on ${candidate_fqdn}..."
    if ! wait_sentinel_sees_priority_bias "${candidate_fqdn}" "$(IFS=','; echo "${all_fqdns[*]}")"; then
      # Sentinel did not reflect the priority in time — restore before aborting
      # so the bias is never left in place after a failed switchover attempt.
      restore_replica_priorities
      return 1
    fi
  fi

  if ! execute_sentinel_failover; then
    # Restore priorities before failing so future Sentinel failovers are not biased.
    if ! is_empty "${candidate_fqdn}"; then
      restore_replica_priorities
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
    restore_replica_priorities
    return "${wfnm_rc}"
  else
    # No candidate: any new master is a valid outcome, but we must confirm one
    # was actually elected. SENTINEL FAILOVER only means the command was accepted;
    # without this check the OpsRequest would report success even if no promotion
    # occurred (e.g. all replicas unreachable).
    if ! wait_for_new_master "" "${KB_SWITCHOVER_CURRENT_FQDN}"; then
      echo "ERROR: Sentinel failover accepted but no new primary confirmed" >&2
      return 1
    fi
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────────
load_common_library

# The action cannot prove the intended transfer without all formal inputs.
if is_empty "${KB_SWITCHOVER_ROLE:-}" ||
   is_empty "${KB_SWITCHOVER_CURRENT_FQDN:-}" ||
   is_empty "${VALKEY_COMPONENT_NAME:-}"; then
  echo "ERROR: KB_SWITCHOVER_ROLE, KB_SWITCHOVER_CURRENT_FQDN, and VALKEY_COMPONENT_NAME are required" >&2
  exit 1
fi

if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
  echo "ERROR: switchover only supports the primary role (got '${KB_SWITCHOVER_ROLE}')." >&2
  exit 1
fi

# ── Sentinel path ──
if ! is_empty "${SENTINEL_COMPONENT_NAME}" && ! is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  echo "Sentinel detected — delegating failover to Sentinel."
  switchover_with_sentinel "${KB_SWITCHOVER_CANDIDATE_FQDN}" || exit 1
  echo "Sentinel switchover complete."
  exit 0
fi

# ── No-Sentinel path ──
echo "ERROR: switchover is unsupported without Sentinel; refusing manual best-effort promotion." >&2
exit 1
