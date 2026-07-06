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
  echo "ERROR: no reachable in-shard replica available as switchover candidate." >&2
  return 1
}

execute_switchover() {
  local candidate="${1}" out
  role=$(role_of "${candidate}")
  if [ "${role}" = "master" ]; then
    echo "candidate ${candidate} is already master — switchover already effective."
    return 0
  fi
  if [ "${role}" != "replica" ]; then
    echo "ERROR: candidate ${candidate} reports role '${role}' — cannot promote (unknown state is not promotable)." >&2
    return 1
  fi
  build_cli "${candidate}"
  out=$("${_cli[@]}" CLUSTER FAILOVER 2>&1) || {
    echo "ERROR: CLUSTER FAILOVER on ${candidate} failed: ${out}" >&2
    return 1
  }
  echo "CLUSTER FAILOVER issued on ${candidate}: ${out}"
  confirm_promotion "${candidate}"
}

confirm_promotion() {
  local candidate="${1}" waited=0 role
  while [ "${waited}" -lt "${SWITCHOVER_CONFIRM_BUDGET}" ]; do
    role=$(role_of "${candidate}")
    if [ "${role}" = "master" ]; then
      echo "switchover confirmed: ${candidate} is master (after ${waited}s)."
      return 0
    fi
    sleep_when_ut_mode_false 1
    waited=$((waited + 1))
  done
  echo "ERROR: candidate ${candidate} did not report master within ${SWITCHOVER_CONFIRM_BUDGET}s — switchover unconfirmed (engine may still complete it; safe to retry)." >&2
  return 1
}

switchover() {
  if [ -z "${CURRENT_SHARD_POD_FQDN_LIST:-}" ]; then
    echo "ERROR: CURRENT_SHARD_POD_FQDN_LIST is required." >&2
    return 1
  fi
  local candidate="${KB_SWITCHOVER_CANDIDATE_FQDN:-}"
  if [ -z "${candidate}" ]; then
    candidate=$(pick_candidate) || return 1
    echo "no candidate specified — deterministically selected ${candidate}."
  fi
  execute_switchover "${candidate}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
switchover
