#!/bin/bash
# valkey-cluster-switchover.sh — intra-shard switchover for Valkey Cluster
# (sharding) mode. Phase C of issue #3021 (issue #3037).
#
# Uses the engine-native graceful path: CLUSTER FAILOVER executed ON the
# promotion candidate (a replica of this shard). No priority biasing, no
# external coordinator — the cluster's own config-epoch machinery guarantees
# consistency.
#
# KB injects (switchover contract):
#   KB_SWITCHOVER_CANDIDATE_FQDN  optional — the replica to promote
#   KB_SWITCHOVER_CURRENT_FQDN    the current primary's FQDN
#   KB_SWITCHOVER_ROLE            role being switched away from ("primary")
#
# Candidate-less switchover picks the lexicographically first in-shard
# replica — deterministic, never random.
#
# Bounded confirmation: the action verifies the candidate actually reports
# master within SWITCHOVER_CONFIRM_BUDGET seconds (default 30, inside the
# action timeout) and fails with a classified error otherwise.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${SERVICE_PORT:-6379}"
SWITCHOVER_CONFIRM_BUDGET="${SWITCHOVER_CONFIRM_BUDGET:-30}"

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

classify() {
  local phase="$1" retry_safe="$2"; shift 2
  echo "action=valkey-cluster-switchover phase=${phase} retry_safe=${retry_safe} detail=$*" >&2
}

build_cli() {
  local host="${1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${port}")
  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    _cli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

role_of() {
  local host="${1}" myself
  build_cli "${host}"
  myself=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | awk '$3 ~ /myself/ {print $3}')
  case "${myself}" in
    *master*) echo "master" ;;
    *slave*)  echo "replica" ;;
    *)        echo "unknown" ;;
  esac
}

# Deterministic candidate pick: first (sorted) in-shard pod that is
# currently a replica and answers. Hard-fails when none qualifies.
pick_candidate() {
  local fqdn role
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    [ "${fqdn}" = "${KB_SWITCHOVER_CURRENT_FQDN}" ] && continue
    role=$(role_of "${fqdn}")
    if [ "${role}" = "replica" ]; then
      echo "${fqdn}"
      return 0
    fi
  done
  classify candidate-pick no "no reachable in-shard replica available as switchover candidate"
  return 1
}

# The candidate must be a replica ATTACHED TO THIS SHARD'S MASTER — its
# own myself line must reference a master id that belongs to an in-shard
# pod (cross-shard replicas are refused).
candidate_replicates_this_shard() {
  local candidate="${1}" myself master_id master_line fqdn pattern="" flags
  build_cli "${candidate}"
  myself=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | awk '$3 ~ /myself/')
  [ -z "${myself}" ] && return 1
  [ "$(echo "${myself}" | grep -c .)" -eq 1 ] || return 1
  flags=$(echo "${myself}" | awk '{print $3}')
  case ",${flags}," in
    *,fail,*|*,handshake,*|*,noaddr,*) return 1 ;;
  esac
  [ "$(echo "${myself}" | awk '{print $8}')" = "connected" ] || return 1
  master_id=$(echo "${myself}" | awk '{print $4}')
  [ "${master_id}" = "-" ] && return 1
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$'); do
    pattern="${pattern:+${pattern}|}${fqdn}"
  done
  master_line=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | awk -v id="${master_id}" '$1 == id')
  [ "$(echo "${master_line}" | grep -c .)" -eq 1 ] || return 1
  flags=$(echo "${master_line}" | awk '{print $3}')
  case ",${flags}," in
    *,fail,*|*,handshake,*|*,noaddr,*) return 1 ;;
  esac
  [ "$(echo "${master_line}" | awk '{print $8}')" = "connected" ] &&
    echo "${master_line}" | grep -qE "${pattern}"
}

line_for_fqdn() {
  local nodes="${1}" fqdn="${2}" lines count
  lines=$(printf '%s\n' "${nodes}" | grep -F "${fqdn}")
  count=$(printf '%s\n' "${lines}" | grep -c .)
  [ "${count}" -eq 1 ] || return 1
  printf '%s\n' "${lines}"
}

line_is_healthy_connected() {
  local line="${1}" flags
  flags=$(printf '%s\n' "${line}" | awk '{print $3}')
  case ",${flags}," in
    *,fail,*|*,handshake,*|*,noaddr,*) return 1 ;;
  esac
  [ "$(printf '%s\n' "${line}" | awk '{print $8}')" = "connected" ]
}

line_owns_slots() {
  printf '%s\n' "${1}" | awk '
    {
      for (i=9; i<=NF; i++) {
        if ($i ~ /^[0-9]+(-[0-9]+)?$/) exit 0
      }
      exit 1
    }
  '
}

# One fresh topology read must prove the complete switchover fact: the
# candidate is the shard's only master and owns slots, while the old primary
# is a healthy replica of that candidate.
switchover_converged() {
  local candidate="${1}" current="${2}" nodes fqdn line flags
  local shard_lines="" master_lines candidate_line current_line candidate_id
  build_cli "${candidate}"
  nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r') || return 1
  [ -n "${nodes}" ] || return 1
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$'); do
    line=$(line_for_fqdn "${nodes}" "${fqdn}") || return 1
    shard_lines="${shard_lines}${shard_lines:+$'\n'}${line}"
  done
  master_lines=$(printf '%s\n' "${shard_lines}" | awk '$3 ~ /(^|,)master(,|$)/')
  [ "$(printf '%s\n' "${master_lines}" | grep -c .)" -eq 1 ] || return 1
  candidate_line=$(line_for_fqdn "${nodes}" "${candidate}") || return 1
  current_line=$(line_for_fqdn "${nodes}" "${current}") || return 1
  [ "${candidate_line}" = "${master_lines}" ] || return 1
  line_is_healthy_connected "${candidate_line}" || return 1
  line_owns_slots "${candidate_line}" || return 1
  candidate_id=$(printf '%s\n' "${candidate_line}" | awk '{print $1}')
  line_is_healthy_connected "${current_line}" || return 1
  flags=$(printf '%s\n' "${current_line}" | awk '{print $3}')
  printf '%s\n' "${flags}" | grep -Eq '(^|,)slave(,|$)' || return 1
  [ "$(printf '%s\n' "${current_line}" | awk '{print $4}')" = "${candidate_id}" ]
}

execute_switchover() {
  local candidate="${1}" out
  role=$(role_of "${candidate}")
  if [ "${role}" = "master" ]; then
    if switchover_converged "${candidate}" "${KB_SWITCHOVER_CURRENT_FQDN}"; then
      echo "candidate ${candidate} is already the authoritative shard master — switchover effective."
      return 0
    fi
    classify failover-confirm yes "candidate ${candidate} self-reports master but shard-wide slot ownership and old-primary demotion are not yet proven"
    return 1
  fi
  if [ "${role}" != "replica" ]; then
    classify candidate-state no "candidate ${candidate} reports role '${role}' — cannot promote (unknown state is not promotable)"
    return 1
  fi
  if ! candidate_replicates_this_shard "${candidate}"; then
    classify candidate-wrong-master no "candidate ${candidate} does not replicate this shard's master — refusing promotion"
    return 1
  fi
  build_cli "${candidate}"
  out=$("${_cli[@]}" CLUSTER FAILOVER 2>&1) || {
    classify failover-issue no "CLUSTER FAILOVER on ${candidate} failed: ${out}"
    return 1
  }
  echo "CLUSTER FAILOVER issued on ${candidate}: ${out}"
  confirm_promotion "${candidate}"
}

confirm_promotion() {
  local candidate="${1}" waited=0
  while [ "${waited}" -lt "${SWITCHOVER_CONFIRM_BUDGET}" ]; do
    if switchover_converged "${candidate}" "${KB_SWITCHOVER_CURRENT_FQDN}"; then
      echo "switchover confirmed from one fresh topology: ${candidate} owns the shard slots and ${KB_SWITCHOVER_CURRENT_FQDN} is its replica (after ${waited}s)."
      return 0
    fi
    sleep_when_ut_mode_false 1
    waited=$((waited + 1))
  done
  classify failover-confirm yes "authoritative shard topology did not converge within ${SWITCHOVER_CONFIRM_BUDGET}s — unconfirmed, safe to retry"
  return 1
}

# Explicit-candidate contract (review blocker): a supplied candidate must
# (a) belong to THIS shard's KB roster, (b) not be the pod being switched
# away from, and (c) currently be a replica whose master is this shard's
# master — a cross-shard or mis-attached candidate must never be promoted.
validate_explicit_candidate() {
  local candidate="${1}"
  if ! echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -qxF "${candidate}"; then
    classify candidate-outside-shard no "candidate ${candidate} is not in CURRENT_SHARD_POD_FQDN_LIST — refusing cross-shard promotion"
    return 1
  fi
  if [ "${candidate}" = "${KB_SWITCHOVER_CURRENT_FQDN:-}" ]; then
    classify candidate-is-current no "candidate equals the current primary — nothing to switch"
    return 1
  fi
  return 0
}

switchover() {
  if [ -z "${CURRENT_SHARD_POD_FQDN_LIST:-}" ] ||
     [ -z "${KB_SWITCHOVER_CURRENT_FQDN:-}" ] ||
     [ -z "${KB_SWITCHOVER_ROLE:-}" ]; then
    classify env-contract no "CURRENT_SHARD_POD_FQDN_LIST, KB_SWITCHOVER_CURRENT_FQDN, and KB_SWITCHOVER_ROLE are required"
    return 1
  fi
  # Only primary switchover is a promotion; any other role request must not
  # take the CLUSTER FAILOVER path (review blocker: KB_SWITCHOVER_ROLE guard).
  if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
    classify role-guard no "switchover requested for role '${KB_SWITCHOVER_ROLE}' — only primary switchover is supported in cluster mode"
    return 1
  fi
  local candidate="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"
  if [ -n "${candidate}" ]; then
    validate_explicit_candidate "${candidate}" || return 1
  else
    candidate=$(pick_candidate) || return 1
    echo "no candidate specified — deterministically selected ${candidate}."
  fi
  execute_switchover "${candidate}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
switchover
