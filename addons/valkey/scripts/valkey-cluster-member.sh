#!/bin/bash
# valkey-cluster-member.sh — intra-shard replica join/leave for Valkey
# Cluster (sharding) mode. Phase C of issue #3021 (issue #3037).
#
# Modes:
#   --join    attach KB_JOIN_MEMBER_POD_FQDN as a replica of this shard's
#             current master (engine node id resolved fresh)
#   --leave   remove KB_LEAVE_MEMBER_POD_FQDN from the cluster; when the
#             leaving pod is the CURRENT master, fail over to another
#             in-shard replica first and only delete after the shard's
#             slots are owned by the new master
#
# Same single-shot discipline as the manage script: positive observation or
# classified non-zero exit; topology re-read every invocation; identity is
# always the engine node id.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${SERVICE_PORT:-6379}"
LEAVE_FAILOVER_BUDGET="${LEAVE_FAILOVER_BUDGET:-30}"

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

# Stable classification for every non-zero exit (aligned with
# valkey-cluster-manage.sh): classify <phase> <retry_safe:yes|no> <detail...>
classify() {
  local phase="$1" retry_safe="$2"; shift 2
  echo "action=valkey-cluster-member phase=${phase} retry_safe=${retry_safe} detail=$*" >&2
}

build_cli() {
  local host="${1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${port}")
  [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ] && _cli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

build_cluster_cli() {
  _ccli=(valkey-cli --no-auth-warning)
  [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ] && _ccli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    _ccli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# Vantage for cluster-view reads: first in-shard pod that (a) is NOT the
# operation target (a target's local view can false-close join/leave —
# review blocker), (b) answers PING, and (c) provably belongs to a FORMED
# cluster (state ok). Never an identity, only a viewpoint.
shard_vantage() {
  local exclude="${1:-}" fqdn state
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    [ -n "${exclude}" ] && [ "${fqdn}" = "${exclude}" ] && continue
    build_cli "${fqdn}"
    "${_cli[@]}" PING 2>/dev/null | grep -q PONG || continue
    state=$("${_cli[@]}" CLUSTER INFO 2>/dev/null | grep "^cluster_state:" | tr -d '\r' | cut -d: -f2)
    if [ "${state}" = "ok" ]; then
      echo "${fqdn}"
      return 0
    fi
  done
  classify vantage yes "no non-target in-shard pod with cluster_state:ok — cannot read a trustworthy cluster view"
  return 1
}

shard_master_line() {
  local via="${1}" fqdn pattern=""
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$'); do
    pattern="${pattern:+${pattern}|}${fqdn}"
  done
  build_cli "${via}"
  "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -E "${pattern}" | awk '$3 ~ /master/ {print; exit}'
}

node_line_of() {
  local via="${1}" target="${2}"
  build_cli "${via}"
  "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -F "${target}" | head -1
}

member_join() {
  local target="${KB_JOIN_MEMBER_POD_FQDN:-}"
  if [ -z "${target}" ]; then
    classify env-contract no "KB_JOIN_MEMBER_POD_FQDN is required for --join"
    exit 1
  fi
  local via master_line master_id master_addr
  via=$(shard_vantage "${target}") || exit 1
  master_line=$(shard_master_line "${via}")
  if [ -z "${master_line}" ]; then
    classify join-no-master no "shard has no master in cluster view — refusing to attach a replica blind"
    exit 1
  fi
  master_id=$(echo "${master_line}" | awk '{print $1}')
  master_addr=$(echo "${master_line}" | awk '{print $2}' | cut -d@ -f1 | cut -d: -f1)

  if join_confirmed "${via}" "${target}" "${master_id}"; then
    echo "member ${target} already a replica of this shard's master — join already effective."
    exit 0
  fi
  if [ -z "$(node_line_of "${via}" "${target}")" ]; then
    build_cluster_cli
    local out
    out=$("${_ccli[@]}" --cluster add-node "${target}:${port}" "${master_addr}:${port}" --cluster-slave --cluster-master-id "${master_id}" 2>&1) || {
      classify join-add-node no "add-node --cluster-slave for ${target} failed: ${out}"
      exit 1
    }
  fi
  if ! join_confirmed "${via}" "${target}" "${master_id}"; then
    classify join-confirm yes "${target} not yet a replica of master ${master_id} in the non-target cluster view"
    exit 1
  fi
  echo "member ${target} joined shard as replica of ${master_id}."
  exit 0
}

# Positive join fact: from a NON-TARGET vantage, the target's node line must
# carry the slave flag AND reference this shard's master id (visibility
# alone is not membership — review blocker).
join_confirmed() {
  local via="${1}" target="${2}" master_id="${3}" line
  line=$(node_line_of "${via}" "${target}")
  [ -z "${line}" ] && return 1
  echo "${line}" | awk '{print $3}' | grep -q slave || return 1
  [ "$(echo "${line}" | awk '{print $4}')" = "${master_id}" ]
}

member_leave() {
  local target="${KB_LEAVE_MEMBER_POD_FQDN:-}"
  if [ -z "${target}" ]; then
    classify env-contract no "KB_LEAVE_MEMBER_POD_FQDN is required for --leave"
    exit 1
  fi
  local via target_line target_id target_flags
  via=$(shard_vantage "${target}") || exit 1
  target_line=$(node_line_of "${via}" "${target}")
  if [ -z "${target_line}" ]; then
    echo "member ${target} not in cluster view — leave already effective."
    exit 0
  fi
  target_id=$(echo "${target_line}" | awk '{print $1}')
  target_flags=$(echo "${target_line}" | awk '{print $3}')

  if echo "${target_flags}" | grep -q master; then
    demote_master_before_leave "${via}" "${target}" || exit 1
  fi

  build_cluster_cli
  local out
  out=$("${_ccli[@]}" --cluster del-node "${via}:${port}" "${target_id}" 2>&1) || {
    classify leave-del-node no "del-node ${target_id} failed: ${out}"
    exit 1
  }
  if [ -n "$(node_line_of "${via}" "${target}")" ]; then
    classify leave-confirm yes "del-node reported success but ${target} still in cluster view"
    exit 1
  fi
  echo "member ${target} removed from cluster."
  exit 0
}

# The leaving pod is the shard's current master: promote another in-shard
# replica via CLUSTER FAILOVER and positively confirm the mastership moved
# before allowing deletion (slots must never be orphaned).
demote_master_before_leave() {
  local via="${1}" leaving="${2}" fqdn role out waited=0
  local promoted=""
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    [ "${fqdn}" = "${leaving}" ] && continue
    build_cli "${fqdn}"
    if "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | awk '$3 ~ /myself/ {print $3}' | grep -q slave; then
      promoted="${fqdn}"
      break
    fi
  done
  if [ -z "${promoted}" ]; then
    classify leave-orphan-guard no "leaving pod is the shard master and no in-shard replica exists — refusing leave (would orphan slots)"
    return 1
  fi
  build_cli "${promoted}"
  out=$("${_cli[@]}" CLUSTER FAILOVER 2>&1) || {
    classify leave-failover no "CLUSTER FAILOVER on ${promoted} failed: ${out}"
    return 1
  }
  while [ "${waited}" -lt "${LEAVE_FAILOVER_BUDGET}" ]; do
    if shard_master_line "${via}" | grep -qF "${promoted}"; then
      echo "mastership moved to ${promoted}; leaving pod is now a replica."
      return 0
    fi
    sleep_when_ut_mode_false 1
    waited=$((waited + 1))
  done
  classify leave-failover-confirm yes "mastership did not move within ${LEAVE_FAILOVER_BUDGET}s — refusing to delete the master"
  return 1
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
case "${1:-}" in
  --join)  member_join ;;
  --leave) member_leave ;;
  *)
    echo "usage: $0 --join | --leave" >&2
    exit 1 ;;
esac
