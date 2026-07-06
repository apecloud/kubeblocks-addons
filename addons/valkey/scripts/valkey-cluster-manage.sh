#!/bin/bash
# valkey-cluster-manage.sh — cluster formation and shard scale for Valkey
# Cluster (sharding) mode. Phase B of issue #3021 (issue #3026).
#
# Modes:
#   --post-provision   form the cluster (coordinator) or verify/join (others)
#   --shard-remove     drain this shard's slots, prove zero, remove its nodes
#
# Contract (single-shot bootstrap-or-defer, kbagent 60s clamp):
#   Every invocation either POSITIVELY observes its goal state and exits 0,
#   or classifies the deferral on stderr and exits 1 for the framework to
#   retry. No in-script long polling; no random sleeps. Topology (CLUSTER
#   NODES / INFO) is re-read on every invocation — never cached across runs.
#
# Coordinator election is deterministic: the lexicographically first shard
# short name in ALL_SHARDS_COMPONENT_SHORT_NAMES owns formation, executed
# from its lexicographically first pod. Empty/duplicated inputs hard-fail —
# never fall back to "current pod" (design review, Slock #valkey:a7e4c67f).
#
# Member identity is always the engine-native CLUSTER MYID — pod names are
# only transport addresses, never identity.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

# Structured classification for every non-zero exit (stable, parseable):
#   classify <phase> <retry_safe:yes|no> <detail...>
classify() {
  local phase="$1" retry_safe="$2"; shift 2
  echo "action=valkey-cluster-manage phase=${phase} retry_safe=${retry_safe} detail=$*" >&2
}

# ── env contract ─────────────────────────────────────────────────────────────

validate_manage_env() {
  local missing=""
  [ -z "${CURRENT_POD_NAME:-}" ] && missing="${missing} CURRENT_POD_NAME"
  [ -z "${CURRENT_SHARD_COMPONENT_SHORT_NAME:-}" ] && missing="${missing} CURRENT_SHARD_COMPONENT_SHORT_NAME"
  [ -z "${CURRENT_SHARD_POD_FQDN_LIST:-}" ] && missing="${missing} CURRENT_SHARD_POD_FQDN_LIST"
  [ -z "${ALL_SHARDS_COMPONENT_SHORT_NAMES:-}" ] && missing="${missing} ALL_SHARDS_COMPONENT_SHORT_NAMES"
  [ -z "${SERVICE_PORT:-}" ] && missing="${missing} SERVICE_PORT"
  if [ -n "${missing}" ]; then
    classify env-contract no "missing required env:${missing} (no fallback)"
    return 1
  fi
  return 0
}

# ── cli helpers ──────────────────────────────────────────────────────────────

build_cli() {
  local host="${1}"
  _cli=(valkey-cli --no-auth-warning -h "${host}" -p "${SERVICE_PORT}")
  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    _cli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    _cli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# --cluster subcommands authenticate the same way
build_cluster_cli() {
  _ccli=(valkey-cli --no-auth-warning)
  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    _ccli+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if [ -n "${VALKEY_CLI_TLS_ARGS:-}" ]; then
    # shellcheck disable=SC2206
    _ccli+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

cluster_state_of() {
  local host="${1}"
  build_cli "${host}"
  "${_cli[@]}" CLUSTER INFO 2>/dev/null | grep "^cluster_state:" | tr -d '\r' | cut -d: -f2
}

assigned_slots_of() {
  local host="${1}"
  build_cli "${host}"
  "${_cli[@]}" CLUSTER INFO 2>/dev/null | grep "^cluster_slots_assigned:" | tr -d '\r' | cut -d: -f2
}

node_id_of() {
  local host="${1}"
  build_cli "${host}"
  "${_cli[@]}" CLUSTER MYID 2>/dev/null | tr -d '\r\n'
}

# Slot count currently owned by the master whose id is $2, read from $1's
# view of CLUSTER NODES. Prints the count of slot ranges' total slots.
slots_owned_by() {
  local via_host="${1}" node_id="${2}"
  local line ranges total=0 range
  build_cli "${via_host}"
  line=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | awk -v id="${node_id}" '$1 == id')
  [ -z "${line}" ] && { echo "-1"; return 0; }
  ranges=$(echo "${line}" | cut -d' ' -f9-)
  for range in ${ranges}; do
    case "${range}" in
      \[*\]) continue ;;  # migrating/importing markers
      *-*) total=$(( total + ${range#*-} - ${range%-*} + 1 )) ;;
      ''|*[!0-9]*) continue ;;
      *) total=$(( total + 1 )) ;;
    esac
  done
  echo "${total}"
}

# ── deterministic coordinator ────────────────────────────────────────────────

# Prints the coordinator shard short name. Hard-fails on empty/duplicate
# entries — an unstable input must stop the action, not pick "myself".
coordinator_shard() {
  local raw="${ALL_SHARDS_COMPONENT_SHORT_NAMES}"
  local entry name names=""
  IFS=',' read -ra _entries <<< "${raw}"
  for entry in "${_entries[@]}"; do
    name="${entry%%:*}"
    [ -z "${name}" ] && { echo "ERROR: empty shard name in ALL_SHARDS_COMPONENT_SHORT_NAMES='${raw}'." >&2; return 1; }
    if echo "${names}" | tr ' ' '\n' | grep -qx "${name}"; then
      echo "ERROR: duplicate shard name '${name}' in ALL_SHARDS_COMPONENT_SHORT_NAMES='${raw}'." >&2
      return 1
    fi
    names="${names} ${name}"
  done
  [ -z "${names// }" ] && { echo "ERROR: ALL_SHARDS_COMPONENT_SHORT_NAMES is empty." >&2; return 1; }
  echo "${names}" | tr ' ' '\n' | grep -v '^$' | sort | head -1
}

# All shard FQDN lists are exposed as ALL_SHARDS_POD_FQDN_LIST_<SHARD-SUFFIX>
# env vars (KB 'individual' strategy). Prints "shard fqdn1,fqdn2" per line.
each_shard_fqdn_list() {
  local var value shard
  while IFS='=' read -r var value; do
    shard="${var#ALL_SHARDS_POD_FQDN_LIST_}"
    [ -z "${value}" ] && { echo "ERROR: ${var} is empty." >&2; return 1; }
    echo "${shard} ${value}"
  done < <(env | grep -E '^ALL_SHARDS_POD_FQDN_LIST_[A-Za-z0-9_]+=' | sort)
}

first_fqdn_of_list() {
  echo "${1}" | tr ',' '\n' | grep -v '^$' | sort | head -1
}

self_is_coordinator_pod() {
  local coord_shard="${1}"
  local self_short_upper coord_upper
  # env var suffixes are uppercased with '-' mapped to '_'
  coord_upper=$(echo "${coord_shard}" | tr '[:lower:]-' '[:upper:]_')
  self_short_upper=$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_')
  [ "${self_short_upper}" != "${coord_upper}" ] && return 1
  local my_shard_first
  my_shard_first=$(first_fqdn_of_list "${CURRENT_SHARD_POD_FQDN_LIST}")
  [ "${my_shard_first%%.*}" = "${CURRENT_POD_NAME}" ]
}

# ── formation ────────────────────────────────────────────────────────────────

# Positive goal check used by every path: state ok and all 16384 slots
# assigned, observed from this pod.
cluster_formed_from_self() {
  local state slots
  state=$(cluster_state_of "127.0.0.1")
  slots=$(assigned_slots_of "127.0.0.1")
  [ "${state}" = "ok" ] && [ "${slots}" = "16384" ] && all_expected_members_present "127.0.0.1"
}

# Positive membership completeness: EVERY pod of EVERY shard (KB roster)
# must appear in the cluster view seen from $1, and every shard must have
# a master there. rc=0 must never settle for state/slot totals alone
# (review: totals can be right while pods are missing or unattached).
all_expected_members_present() {
  local via="${1}" nodes shard_line shard fqdns fqdn missing=0
  build_cli "${via}"
  nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
  [ -z "${nodes}" ] && return 1
  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    for fqdn in $(echo "${fqdns}" | tr ',' '\n' | grep -v '^$'); do
      if ! echo "${nodes}" | grep -qF "${fqdn}"; then
        echo "membership incomplete: ${fqdn} (shard ${shard}) not in cluster view."
        missing=1
      fi
    done
    if [ "$(echo "${nodes}" | grep -E "$(echo "${fqdns}" | tr ',' '|')" | awk '$3 ~ /master/' | grep -c .)" -lt 1 ]; then
      echo "membership incomplete: shard ${shard} has no master in cluster view."
      missing=1
    fi
  done < <(each_shard_fqdn_list)
  [ "${missing}" -eq 0 ]
}

# Coordinator: create the cluster from one designated first-pod per shard,
# then attach the remaining pods of each shard as replicas of that shard's
# master. The first-pod choice is an ASSIGNMENT at creation time (roles may
# move later via failover) — never an assumption elsewhere.
form_cluster() {
  local shard_line shard fqdns first rest fqdn
  local primaries=()

  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    first=$(first_fqdn_of_list "${fqdns}")
    # every designated primary must answer before creation — else defer
    if ! build_cli "${first}" || ! "${_cli[@]}" PING 2>/dev/null | grep -q PONG; then
      classify formation-wait-primaries yes "shard ${shard} first pod ${first} not answering yet"
      return 1
    fi
    primaries+=("${first}:${SERVICE_PORT}")
  done < <(each_shard_fqdn_list)

  if [ "${#primaries[@]}" -lt 3 ]; then
    classify formation-wait-shards yes "only ${#primaries[@]} shard(s) visible; create needs >=3"
    return 1
  fi

  build_cluster_cli
  local create_out
  create_out=$(echo yes | "${_ccli[@]}" --cluster create "${primaries[@]}" --cluster-yes 2>&1) || {
    classify formation-create no "cluster create failed: ${create_out}"
    return 1
  }
  echo "cluster create issued across ${#primaries[@]} primaries."

  attach_all_replicas || return 1
  cluster_formed_from_self || {
    classify formation-converge yes "create issued but state/slots/membership not converged yet"
    return 1
  }
  echo "cluster formed: state ok, 16384/16384 slots assigned."
}

# Attach every non-first pod of every shard as a replica of that shard's
# master (identified by engine node id, resolved fresh each invocation).
attach_all_replicas() {
  local shard_line shard fqdns first rest fqdn master_id add_out
  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    first=$(first_fqdn_of_list "${fqdns}")
    master_id=$(node_id_of "${first}")
    if [ -z "${master_id}" ]; then
      classify formation-myid yes "cannot read CLUSTER MYID from ${first}"
      return 1
    fi
    for fqdn in $(echo "${fqdns}" | tr ',' '\n' | grep -v '^$' | sort); do
      [ "${fqdn}" = "${first}" ] && continue
      # already a member? (idempotency: skip nodes the master already knows)
      build_cli "${first}"
      if "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -q "${fqdn}"; then
        continue
      fi
      build_cluster_cli
      add_out=$("${_ccli[@]}" --cluster add-node "${fqdn}:${SERVICE_PORT}" "${first}:${SERVICE_PORT}" --cluster-slave --cluster-master-id "${master_id}" 2>&1) || {
        classify formation-add-replica no "add replica ${fqdn} to shard ${shard} failed: ${add_out}"
        return 1
      }
      echo "attached ${fqdn} as replica of shard ${shard} (master ${master_id})."
    done
  done < <(each_shard_fqdn_list)
}

# Non-coordinator (or late shard) path: if the cluster is formed and this
# shard's members are attached, succeed; if formed but self not attached,
# join as the scale-out path; otherwise defer.
verify_or_join() {
  local any_formed_host="" shard_line fqdns first state
  while read -r shard_line; do
    fqdns="${shard_line#* }"
    first=$(first_fqdn_of_list "${fqdns}")
    state=$(cluster_state_of "${first}")
    if [ "${state}" = "ok" ]; then
      any_formed_host="${first}"
      break
    fi
  done < <(each_shard_fqdn_list)

  if [ -z "${any_formed_host}" ]; then
    classify join-wait-formed yes "no formed cluster visible yet (coordinator still working)"
    return 1
  fi

  local self_first master_id
  self_first=$(first_fqdn_of_list "${CURRENT_SHARD_POD_FQDN_LIST}")
  build_cli "${any_formed_host}"
  if "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -q "${self_first}"; then
    if all_expected_members_present "${any_formed_host}"; then
      echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} already a cluster member; membership complete."
      return 0
    fi
    classify join-membership yes "shard present but full membership not yet complete"
    return 1
  fi

  # scale-out: join this shard's first pod as a new master, rebalance slots
  # to it, then attach the shard's replicas.
  build_cluster_cli
  local add_out
  add_out=$("${_ccli[@]}" --cluster add-node "${self_first}:${SERVICE_PORT}" "${any_formed_host}:${SERVICE_PORT}" 2>&1) || {
    classify join-add-node no "add-node ${self_first} failed: ${add_out}"
    return 1
  }
  master_id=$(node_id_of "${self_first}")
  if [ -z "${master_id}" ]; then
    classify join-myid yes "joined but CLUSTER MYID unreadable from ${self_first}"
    return 1
  fi
  local rebalance_out
  rebalance_out=$("${_ccli[@]}" --cluster rebalance "${any_formed_host}:${SERVICE_PORT}" --cluster-use-empty-masters 2>&1) || {
    classify join-rebalance no "rebalance toward new shard failed: ${rebalance_out}"
    return 1
  }
  attach_shard_replicas_to "${self_first}" "${master_id}" || return 1
  local own
  own=$(slots_owned_by "${self_first}" "${master_id}")
  if [ "${own}" -le 0 ]; then
    classify join-slots yes "new shard joined but owns ${own} slots after rebalance"
    return 1
  fi
  # positive completeness: every pod of THIS shard must be in the view
  local nodes vfqdn
  build_cli "${self_first}"
  nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
  for vfqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$'); do
    if ! echo "${nodes}" | grep -qF "${vfqdn}"; then
      classify join-membership yes "pod ${vfqdn} of this shard not yet in cluster view"
      return 1
    fi
  done
  echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} joined with ${own} slots; all shard pods in view."
}

attach_shard_replicas_to() {
  local master_fqdn="${1}" master_id="${2}" fqdn add_out
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    [ "${fqdn}" = "${master_fqdn}" ] && continue
    build_cli "${master_fqdn}"
    if "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -q "${fqdn}"; then
      continue
    fi
    build_cluster_cli
    add_out=$("${_ccli[@]}" --cluster add-node "${fqdn}:${SERVICE_PORT}" "${master_fqdn}:${SERVICE_PORT}" --cluster-slave --cluster-master-id "${master_id}" 2>&1) || {
      classify join-add-replica no "add replica ${fqdn} failed: ${add_out}"
      return 1
    }
  done
}

post_provision() {
  validate_manage_env || exit 1
  if cluster_formed_from_self; then
    echo "cluster already formed (state ok, 16384 slots) — nothing to do."
    exit 0
  fi
  local coord
  coord=$(coordinator_shard) || exit 1
  if self_is_coordinator_pod "${coord}"; then
    echo "this pod is the formation coordinator (shard ${coord})."
    form_cluster || exit 1
  else
    verify_or_join || exit 1
  fi
  exit 0
}

# ── shard removal ────────────────────────────────────────────────────────────

# Drain this shard's slots, POSITIVELY prove the slot count is zero, then —
# and only then — remove the shard's nodes from the cluster. del-node
# success alone is never the completion signal (design review hard line).
shard_remove() {
  validate_manage_env || exit 1

  local remaining_host="" shard_line shard fqdns first
  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    [ "${shard}" = "$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_')" ] && continue
    first=$(first_fqdn_of_list "${fqdns}")
    if [ "$(cluster_state_of "${first}")" = "ok" ]; then
      remaining_host="${first}"
      break
    fi
  done < <(each_shard_fqdn_list)
  if [ -z "${remaining_host}" ]; then
    classify remove-no-receiver no "no healthy remaining shard visible to receive slots — refusing removal"
    exit 1
  fi

  local self_first master_id
  self_first=$(first_fqdn_of_list "${CURRENT_SHARD_POD_FQDN_LIST}")
  # the shard's CURRENT master may not be the first pod (failovers move
  # roles) — resolve the master id from the cluster's own view.
  master_id=$(shard_master_id_via "${remaining_host}")
  if [ -z "${master_id}" ]; then
    # No master of this shard known to the cluster: shard is already out —
    # classify NotFound explicitly as closable only when no slots dangle.
    echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} has no master in cluster view — treating as already removed."
    exit 0
  fi

  local own
  own=$(slots_owned_by "${remaining_host}" "${master_id}")
  if [ "${own}" -gt 0 ]; then
    build_cluster_cli
    local reb_out
    reb_out=$("${_ccli[@]}" --cluster rebalance "${remaining_host}:${SERVICE_PORT}" --cluster-weight "${master_id}=0" 2>&1) || {
      classify remove-drain no "slot drain (rebalance weight=0) failed: ${reb_out}"
      exit 1
    }
    own=$(slots_owned_by "${remaining_host}" "${master_id}")
  fi
  if [ "${own}" -ne 0 ]; then
    classify remove-slots-nonzero yes "shard still owns ${own} slots after drain — NOT removing nodes"
    exit 1
  fi
  echo "slot drain proven: shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} owns 0 slots."

  # remove replicas first, master last
  local node_line node_id fqdn
  build_cli "${remaining_host}"
  while read -r node_line; do
    node_id="${node_line%% *}"
    build_cluster_cli
    local del_out
    del_out=$("${_ccli[@]}" --cluster del-node "${remaining_host}:${SERVICE_PORT}" "${node_id}" 2>&1) || {
      classify remove-del-node no "del-node ${node_id} failed: ${del_out}"
      exit 1
    }
    echo "removed node ${node_id} from cluster."
  done < <(shard_member_lines_via "${remaining_host}" | awk '{if ($3 ~ /slave/) print; }')
  while read -r node_line; do
    node_id="${node_line%% *}"
    build_cluster_cli
    local del_out2
    del_out2=$("${_ccli[@]}" --cluster del-node "${remaining_host}:${SERVICE_PORT}" "${node_id}" 2>&1) || {
      classify remove-del-node no "del-node ${node_id} failed: ${del_out2}"
      exit 1
    }
    echo "removed node ${node_id} from cluster."
  done < <(shard_member_lines_via "${remaining_host}" | awk '{if ($3 ~ /master/) print; }')
  echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} removed cleanly (drained then deleted)."
  exit 0
}

# CLUSTER NODES lines whose address matches any pod of the current shard.
shard_member_lines_via() {
  local via="${1}" fqdn pattern=""
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$'); do
    pattern="${pattern:+${pattern}|}${fqdn}"
  done
  build_cli "${via}"
  "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -E "${pattern}" || true
}

shard_master_id_via() {
  local via="${1}"
  shard_member_lines_via "${via}" | awk '$3 ~ /master/ {print $1; exit}'
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
case "${1:-}" in
  --post-provision) post_provision ;;
  --shard-remove)   shard_remove ;;
  *)
    echo "usage: $0 --post-provision | --shard-remove" >&2
    exit 1 ;;
esac
