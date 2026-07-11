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

known_nodes_of() {
  local host="${1}"
  build_cli "${host}"
  "${_cli[@]}" CLUSTER INFO 2>/dev/null | grep "^cluster_known_nodes:" | tr -d '\r' | cut -d: -f2
}

cluster_nodes_of() {
  local host="${1}"
  build_cli "${host}"
  "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r'
}

cluster_node_id_set() {
  local nodes
  nodes=$(cat)
  printf '%s\n' "${nodes}" | awk '
    NF == 0 {next}
    NF < 8 || $3 !~ /(^|,)(master|slave)(,|$)/ {bad=1; next}
    END {exit bad ? 1 : 0}
  ' >/dev/null || return 1
  printf '%s\n' "${nodes}" | awk 'NF > 0 {print $1}' | LC_ALL=C sort -u
}

node_id_sets_overlap() {
  local left="${1}" right="${2}" id
  while IFS= read -r id; do
    [ -n "${id}" ] || continue
    printf '%s\n' "${right}" | grep -Fqx "${id}" && return 0
  done <<< "${left}"
  return 1
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
    [ -z "${name}" ] && { classify shard-roster no "empty shard name in ALL_SHARDS_COMPONENT_SHORT_NAMES='${raw}'"; return 1; }
    if echo "${names}" | tr ' ' '\n' | grep -qx "${name}"; then
      classify shard-roster no "duplicate shard name '${name}' in ALL_SHARDS_COMPONENT_SHORT_NAMES='${raw}'"
      return 1
    fi
    names="${names} ${name}"
  done
  [ -z "${names// }" ] && { classify shard-roster no "ALL_SHARDS_COMPONENT_SHORT_NAMES is empty"; return 1; }
  echo "${names}" | tr ' ' '\n' | grep -v '^$' | sort | head -1
}

# All shard FQDN lists are exposed as ALL_SHARDS_POD_FQDN_LIST_<SHARD-SUFFIX>
# env vars (KB 'individual' strategy). Prints "shard fqdn1,fqdn2" per line.
#
# CONSUMPTION CONTRACT (fresh-eyes review M1): callers MUST materialize the
# output first (roster=$(each_shard_fqdn_list) || return 1) and iterate the
# variable. Feeding this through a process substitution discards the exit
# status: an empty/missing var would silently TRUNCATE the stream and every
# downstream completeness/absence proof would quietly weaken. Zero roster
# vars is likewise a hard failure, never an empty (vacuously passing) loop.
each_shard_fqdn_list() {
  local var value shard count=0
  while IFS='=' read -r var value; do
    shard="${var#ALL_SHARDS_POD_FQDN_LIST_}"
    [ -z "${value}" ] && { classify shard-roster no "${var} is empty"; return 1; }
    echo "${shard} ${value}"
    count=$((count + 1))
  done < <(env | grep -E '^ALL_SHARDS_POD_FQDN_LIST_[A-Za-z0-9_]+=' | sort)
  if [ "${count}" -eq 0 ]; then
    classify shard-roster no "no ALL_SHARDS_POD_FQDN_LIST_* env vars present (roster unknown)"
    return 1
  fi
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
  local via="${1}" nodes shard_line shard fqdns missing=0 roster
  roster=$(each_shard_fqdn_list) || return 1
  build_cli "${via}"
  nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
  [ -z "${nodes}" ] && return 1
  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    shard_membership_bound "${nodes}" "${shard}" "${fqdns}" || missing=1
  done <<< "${roster}"
  [ "${missing}" -eq 0 ]
}

# Strict per-shard binding (round-2 review): the shard must have exactly
# one in-shard master, and EVERY other in-shard pod's node line must carry
# the slave flag AND reference that master's id. Presence alone would let
# a stray master or a cross-shard replica pass as success.
shard_membership_bound() {
  local nodes="${1}" shard="${2}" fqdns="${3}"
  local pattern="" fqdn line master_line master_id master_count flags parent
  for fqdn in $(echo "${fqdns}" | tr ',' '\n' | grep -v '^$'); do
    pattern="${pattern:+${pattern}|}${fqdn}"
  done
  master_count=$(echo "${nodes}" | grep -E "${pattern}" | awk '$3 ~ /master/' | grep -c .)
  if [ "${master_count}" -ne 1 ]; then
    echo "membership incomplete: shard ${shard} has ${master_count} in-shard master(s), expected exactly 1."
    return 1
  fi
  master_line=$(echo "${nodes}" | grep -E "${pattern}" | awk '$3 ~ /master/ {print; exit}')
  master_id=$(echo "${master_line}" | awk '{print $1}')
  local bad=0
  for fqdn in $(echo "${fqdns}" | tr ',' '\n' | grep -v '^$'); do
    line=$(echo "${nodes}" | grep -F "${fqdn}" | head -1)
    if [ -z "${line}" ]; then
      echo "membership incomplete: ${fqdn} (shard ${shard}) not in cluster view."
      bad=1
      continue
    fi
    flags=$(echo "${line}" | awk '{print $3}')
    case "${flags}" in
      *master*) continue ;;
    esac
    if ! echo "${flags}" | grep -q slave; then
      echo "membership incomplete: ${fqdn} (shard ${shard}) is neither master nor slave (flags=${flags})."
      bad=1
      continue
    fi
    parent=$(echo "${line}" | awk '{print $4}')
    if [ "${parent}" != "${master_id}" ]; then
      echo "membership incomplete: ${fqdn} (shard ${shard}) replicates ${parent}, not this shard's master ${master_id}."
      bad=1
    fi
  done
  return "${bad}"
}

# Coordinator: create the cluster from one designated first-pod per shard,
# then attach the remaining pods of each shard as replicas of that shard's
# master. The first-pod choice is an ASSIGNMENT at creation time (roles may
# move later via failover) — never an assumption elsewhere.
form_cluster() {
  local shard_line shard fqdns first rest fqdn roster node_id slots known
  local primaries=()
  local primary_hosts=() primary_ids=() primary_slots=() primary_known=()

  roster=$(each_shard_fqdn_list) || return 1
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
    primary_hosts+=("${first}")
  done <<< "${roster}"

  if [ "${#primaries[@]}" -lt 3 ]; then
    classify formation-wait-shards yes "only ${#primaries[@]} shard(s) visible; create needs >=3"
    return 1
  fi

  local phost
  for phost in "${primary_hosts[@]}"; do
    node_id=$(node_id_of "${phost}") || {
      classify formation-probe yes "cannot read CLUSTER MYID from designated primary ${phost}"
      return 1
    }
    slots=$(assigned_slots_of "${phost}") || {
      classify formation-probe yes "cannot read assigned slots from designated primary ${phost}"
      return 1
    }
    known=$(known_nodes_of "${phost}") || {
      classify formation-probe yes "cannot read known-node count from designated primary ${phost}"
      return 1
    }
    case "${slots}" in ''|*[!0-9]*) classify formation-probe yes "invalid assigned slots '${slots}' from ${phost}"; return 1 ;; esac
    case "${known}" in ''|*[!0-9]*) classify formation-probe yes "invalid known-node count '${known}' from ${phost}"; return 1 ;; esac
    if [ "${slots}" -gt 16384 ]; then
      classify formation-probe yes "assigned slots ${slots} outside 0..16384 on ${phost}"
      return 1
    fi
    if [ "${known}" -lt 1 ]; then
      classify formation-probe yes "known-node count ${known} must be at least 1 on ${phost}"
      return 1
    fi
    [ -n "${node_id}" ] || {
      classify formation-probe yes "empty CLUSTER MYID from designated primary ${phost}"
      return 1
    }
    primary_ids+=("${node_id}")
    primary_slots+=("${slots}")
    primary_known+=("${known}")
  done

  # RE-ENTRY GUARD: --cluster create is safe only when EVERY designated
  # primary is fresh. A mixed set needs an explicit repair driver; blindly
  # skipping create on the first configured node leaves fresh shard masters
  # forever outside that cluster, while blindly merging two configured
  # clusters risks combining unrelated slot/config-epoch histories.
  local resume="" resume_nodes="" other_nodes="" resume_node_ids="" other_node_ids=""
  local fresh_count=0 i resume_index=-1
  for ((i=0; i<${#primary_hosts[@]}; i++)); do
    if [ "${primary_slots[$i]}" -gt 0 ] || [ "${primary_known[$i]}" -gt 1 ]; then
      if [ -z "${resume}" ]; then
        resume="${primary_hosts[$i]}"
        resume_index=$i
      fi
    else
      fresh_count=$((fresh_count + 1))
    fi
  done
  if [ -n "${resume}" ]; then
    echo "cluster config already present on ${resume} — resuming interrupted formation (create skipped)."

    resume_nodes=$(cluster_nodes_of "${resume}") || {
      classify formation-resume-topology yes "cannot read CLUSTER NODES from resume host ${resume}"
      return 1
    }
    [ -n "${resume_nodes}" ] || {
      classify formation-resume-topology yes "empty CLUSTER NODES from resume host ${resume}"
      return 1
    }
    resume_node_ids=$(printf '%s\n' "${resume_nodes}" | cluster_node_id_set) || {
      classify formation-resume-topology yes "malformed CLUSTER NODES from resume host ${resume}"
      return 1
    }
    [ -n "${resume_node_ids}" ] || {
      classify formation-resume-topology yes "empty node-ID set from resume host ${resume}"
      return 1
    }

    # Every already-configured primary must expose the SAME complete node-ID
    # set. A partially overlapping set is transient gossip; a disjoint set is
    # an independently configured cluster and is never auto-merged.
    for ((i=0; i<${#primary_hosts[@]}; i++)); do
      [ "$i" -eq "${resume_index}" ] && continue
      if [ "${primary_slots[$i]}" -gt 0 ] || [ "${primary_known[$i]}" -gt 1 ]; then
        other_nodes=$(cluster_nodes_of "${primary_hosts[$i]}") || {
          classify formation-resume-topology yes "cannot read CLUSTER NODES from configured primary ${primary_hosts[$i]}"
          return 1
        }
        [ -n "${other_nodes}" ] || {
          classify formation-resume-topology yes "empty CLUSTER NODES from configured primary ${primary_hosts[$i]}"
          return 1
        }
        other_node_ids=$(printf '%s\n' "${other_nodes}" | cluster_node_id_set) || {
          classify formation-resume-topology yes "malformed CLUSTER NODES from configured primary ${primary_hosts[$i]}"
          return 1
        }
        [ -n "${other_node_ids}" ] || {
          classify formation-resume-topology yes "empty node-ID set from configured primary ${primary_hosts[$i]}"
          return 1
        }
        if [ "${resume_node_ids}" = "${other_node_ids}" ]; then
          continue
        fi
        if ! node_id_sets_overlap "${resume_node_ids}" "${other_node_ids}"; then
          classify formation-resume-topology no "configured primary ${primary_hosts[$i]} is not in resume cluster ${resume}; refusing automatic cluster merge"
          return 1
        fi
        classify formation-resume-topology yes "membership gossip between ${resume} and ${primary_hosts[$i]} has a different node-ID set (possibly one-way); deferring before mutation"
        return 1
      fi
    done

    # redis-cli add-node performs cluster-health preflight checks. Repair the
    # resume cluster's slot coverage first so a partially completed create
    # cannot permanently block introduction of the remaining fresh masters.
    slots=$(assigned_slots_of "${resume}")
    if [ "${slots:-0}" -ne 16384 ] 2>/dev/null; then
      build_cluster_cli
      local fix_out
      fix_out=$(echo yes | "${_ccli[@]}" --cluster fix "${resume}:${SERVICE_PORT}" 2>&1) || {
        classify formation-resume yes "slot-coverage fix during formation resume failed (re-entry re-drives): $(echo "${fix_out}" | tail -2 | tr '\n' ';')"
        return 1
      }
      slots=$(assigned_slots_of "${resume}")
      if [ "${slots:-0}" -ne 16384 ] 2>/dev/null; then
        classify formation-resume yes "slot coverage ${slots:-0}/16384 after resume fix — deferring"
        return 1
      fi
    fi

    # Fresh designated primaries are now safe to introduce as empty masters.
    # Re-entry verifies mutual visibility before any slot redistribution.
    if [ "${fresh_count}" -gt 0 ]; then
      build_cluster_cli
      local add_out introduced=0
      for ((i=0; i<${#primary_hosts[@]}; i++)); do
        [ "${primary_slots[$i]}" -eq 0 ] && [ "${primary_known[$i]}" -eq 1 ] || continue
        add_out=$("${_ccli[@]}" --cluster add-node "${primary_hosts[$i]}:${SERVICE_PORT}" "${resume}:${SERVICE_PORT}" 2>&1) || {
          classify formation-resume yes "add missing designated primary ${primary_hosts[$i]} failed (re-entry re-drives): ${add_out}"
          return 1
        }
        introduced=$((introduced + 1))
        echo "introduced missing designated primary ${primary_hosts[$i]} to resume cluster ${resume}."
      done
      classify formation-resume yes "introduced ${introduced} missing designated primary(s); deferring for mutual membership visibility"
      return 1
    fi

    # Interrupted formation can leave a mutually visible master with zero
    # slots. Rebalance only after full coverage and same-cluster proof.
    local zero_slot_primary=0 own rebalance_out
    for ((i=0; i<${#primary_hosts[@]}; i++)); do
      own=$(slots_owned_by "${resume}" "${primary_ids[$i]}") || {
        classify formation-resume yes "cannot read owned slots for designated primary ${primary_hosts[$i]}"
        return 1
      }
      case "${own}" in ''|*[!0-9]*) classify formation-resume yes "invalid owned-slot count '${own}' for designated primary ${primary_hosts[$i]}"; return 1 ;; esac
      [ "${own}" -gt 0 ] || zero_slot_primary=1
    done
    if [ "${zero_slot_primary}" -eq 1 ]; then
      build_cluster_cli
      rebalance_out=$("${_ccli[@]}" --cluster rebalance "${resume}:${SERVICE_PORT}" --cluster-use-empty-masters 2>&1) || {
        classify formation-resume yes "rebalance across resumed designated primaries failed (re-entry re-drives): ${rebalance_out}"
        return 1
      }
      for ((i=0; i<${#primary_hosts[@]}; i++)); do
        own=$(slots_owned_by "${resume}" "${primary_ids[$i]}") || {
          classify formation-resume yes "cannot verify owned slots for designated primary ${primary_hosts[$i]} after resume rebalance"
          return 1
        }
        case "${own}" in ''|*[!0-9]*) classify formation-resume yes "invalid post-rebalance owned-slot count '${own}' for designated primary ${primary_hosts[$i]}"; return 1 ;; esac
        if [ "${own}" -le 0 ]; then
          classify formation-resume yes "designated primary ${primary_hosts[$i]} still owns ${own} slots after resume rebalance"
          return 1
        fi
      done
    fi
  else
    build_cluster_cli
    local create_out
    create_out=$(echo yes | "${_ccli[@]}" --cluster create "${primaries[@]}" --cluster-yes 2>&1) || {
      classify formation-create no "cluster create failed: ${create_out}"
      return 1
    }
    echo "cluster create issued across ${#primaries[@]} primaries."
  fi

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
  local shard_line shard fqdns first rest fqdn master_id add_out roster
  roster=$(each_shard_fqdn_list) || return 1
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
      ensure_replica_bound "${first}" "${fqdn}" "${master_id}" "${shard}" || return 1
    done
  done <<< "${roster}"
}

# Non-coordinator (or late shard) path: if the cluster is formed and this
# shard's members are attached, succeed; if formed but self not attached,
# join as the scale-out path; otherwise defer.
verify_or_join() {
  local any_formed_host="" shard_line fqdns first state roster
  roster=$(each_shard_fqdn_list) || return 1
  while read -r shard_line; do
    fqdns="${shard_line#* }"
    first=$(first_fqdn_of_list "${fqdns}")
    state=$(cluster_state_of "${first}")
    if [ "${state}" = "ok" ]; then
      any_formed_host="${first}"
      break
    fi
  done <<< "${roster}"

  if [ -z "${any_formed_host}" ]; then
    classify join-wait-formed yes "no formed cluster visible yet (coordinator still working)"
    return 1
  fi

  local self_first
  self_first=$(first_fqdn_of_list "${CURRENT_SHARD_POD_FQDN_LIST}")

  # JOIN QUEUE (r11 CT12 3->5 evidence): when MULTIPLE shards join in one
  # operation (Parallel provisioning), concurrent drivers mutually wound
  # each other — each shard's fix/rebalance creates exactly the transient
  # inconsistency that fails the other's preflights, alternating forever.
  # Same design language as formation's deterministic coordinator: among
  # the currently-INCOMPLETE shards (engine truth), only the sorted-first
  # one may perform write actions; the rest defer retry-safe and take
  # their turn on a later re-entry. Completed shards are never gated.
  local first_incomplete
  first_incomplete=$(first_incomplete_shard "${any_formed_host}") || return 1
  if [ -n "${first_incomplete}" ] && \
     [ "${first_incomplete}" != "$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_')" ] && \
     ! shard_complete_in_view "${any_formed_host}" "$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_')"; then
    classify join-queue yes "holder=${first_incomplete} current=$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_') — waiting for earlier joining shard (deterministic multi-join serialization)"
    return 1
  fi

  build_cli "${any_formed_host}"
  if ! "${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -q "${self_first}"; then
    # repair-first also gates the FIRST CONTACT: the turn-holder may
    # inherit open slots left by a clamped predecessor, and add-node's
    # preflight rejects over them (review contract, r11 CT12).
    if open_slots_present "${any_formed_host}"; then
      repair_open_slots "${any_formed_host}" || return 1
    fi
    # scale-out first contact: introduce this shard's designated master.
    # Wrapper preflight failures here are dominated by transient config
    # agreement (gossip settling after a prior step) -> retry-safe defer;
    # re-entry re-reads topology and re-drives (r3 CT05 evidence).
    build_cluster_cli
    local add_out
    add_out=$("${_ccli[@]}" --cluster add-node "${self_first}:${SERVICE_PORT}" "${any_formed_host}:${SERVICE_PORT}" 2>&1) || {
      classify join-add-node yes "add-node ${self_first} failed (re-entry re-drives): ${add_out}"
      return 1
    }
    echo "introduced ${self_first} to the cluster as this shard's master."
  fi
  # DRIVER (r3 CT05 livelock fix): once this shard is visible, every
  # invocation must DRIVE the remaining steps -- slots, replica binding,
  # roster completeness -- never observe-and-defer. The old present-branch
  # deferred without acting, so a single failed attach never healed.
  drive_shard_completion "${any_formed_host}" "${self_first}"
}

# Open-slot detection: an interrupted slot migration (e.g. a rebalance
# killed by the action runtime clamp mid-slot) leaves importing/migrating
# markers the engine never self-heals; every later add-node/rebalance
# preflight then rejects. --cluster check surfaces them from any vantage.
open_slots_present() {
  local via="${1}" out
  build_cluster_cli
  out=$("${_ccli[@]}" --cluster check "${via}:${SERVICE_PORT}" 2>&1) || true
  echo "${out}" | grep -qiE "slots are open|in (migrating|importing) state"
}

# Repair interrupted migrations, then positively re-check. Retry-safe:
# re-entry re-reads engine state and re-drives the fix.
repair_open_slots() {
  local via="${1}" fix_out
  build_cluster_cli
  fix_out=$(echo yes | "${_ccli[@]}" --cluster fix "${via}:${SERVICE_PORT}" 2>&1) || {
    classify join-fix yes "cluster fix for open slots failed (re-entry re-drives): $(echo "${fix_out}" | tail -2 | tr '\n' ';')"
    return 1
  }
  if open_slots_present "${via}"; then
    classify join-fix yes "open slots remain after cluster fix — deferring"
    return 1
  fi
  echo "repaired open slots (interrupted migration)."
}

# A shard is COMPLETE in the cluster view when it has exactly one bound
# master that owns slots and every roster pod is bound (strict binding).
# Used by the join queue; reads engine truth from the given vantage.
shard_complete_in_view() {
  local via="${1}" shard_upper="${2}" shard_line shard fqdns nodes master_line master_id own roster
  roster=$(each_shard_fqdn_list) || return 1
  while read -r shard_line; do
    shard="${shard_line%% *}"
    [ "${shard}" = "${shard_upper}" ] || continue
    fqdns="${shard_line#* }"
    build_cli "${via}"
    nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
    [ -z "${nodes}" ] && return 1
    shard_membership_bound "${nodes}" "${shard}" "${fqdns}" >/dev/null || return 1
    master_line=$(echo "${nodes}" | grep -E "$(echo "${fqdns}" | tr ',' '|')" | awk '$3 ~ /master/ {print; exit}')
    master_id=$(echo "${master_line}" | awk '{print $1}')
    own=$(slots_owned_by "${via}" "${master_id}")
    [ "${own}" -gt 0 ] && return 0
    return 1
  done <<< "${roster}"
  return 1
}

# Sorted-first shard (roster order) that is NOT complete in the view.
# Empty output = all roster shards complete. rc=1 = roster env unreadable
# (callers must defer, never treat as "all complete").
first_incomplete_shard() {
  local via="${1}" shard_line shard roster
  roster=$(each_shard_fqdn_list) || return 1
  while read -r shard_line; do
    shard="${shard_line%% *}"
    if ! shard_complete_in_view "${via}" "${shard}"; then
      echo "${shard}"
      return 0
    fi
  done <<< "${roster}"
  return 0
}

# Idempotent completion driver for THIS shard: ensure its master owns
# slots (rebalance if zero), ensure every replica is bound, then require
# strict in-shard binding and full-roster completeness. Safe to re-enter
# from any partial state; every step re-reads engine truth first.
drive_shard_completion() {
  local via="${1}" self_first="${2}" master_id own
  master_id=$(node_id_of "${self_first}")
  if [ -z "${master_id}" ]; then
    classify join-myid yes "CLUSTER MYID unreadable from ${self_first}"
    return 1
  fi
  # r7 CT05 evidence: repair interrupted migrations FIRST — a stuck open
  # slot blocks both rebalance and replica attach, and own>0 alone must
  # not skip past it.
  if open_slots_present "${via}"; then
    repair_open_slots "${via}" || return 1
  fi
  own=$(slots_owned_by "${via}" "${master_id}")
  if [ "${own}" -le 0 ]; then
    build_cluster_cli
    local rebalance_out
    rebalance_out=$("${_ccli[@]}" --cluster rebalance "${via}:${SERVICE_PORT}" --cluster-use-empty-masters 2>&1) || {
      classify join-rebalance yes "rebalance toward ${CURRENT_SHARD_COMPONENT_SHORT_NAME} failed (re-entry re-drives): ${rebalance_out}"
      return 1
    }
    own=$(slots_owned_by "${via}" "${master_id}")
    if [ "${own}" -le 0 ]; then
      classify join-slots yes "shard master owns ${own} slots after rebalance"
      return 1
    fi
  fi
  attach_shard_replicas_to "${self_first}" "${master_id}" || return 1
  # positive completeness: strict binding for THIS shard (exactly one
  # in-shard master; every other pod a slave of that master)
  local nodes
  build_cli "${self_first}"
  nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
  if ! shard_membership_bound "${nodes}" "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" "${CURRENT_SHARD_POD_FQDN_LIST}"; then
    classify join-membership yes "this shard's pods not yet fully bound (master+replicas) in cluster view"
    return 1
  fi
  if ! all_expected_members_present "${via}"; then
    classify join-membership yes "this shard complete; full roster membership not yet complete"
    return 1
  fi
  echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} complete: ${own} slots, membership bound."
}

attach_shard_replicas_to() {
  local master_fqdn="${1}" master_id="${2}" fqdn
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    [ "${fqdn}" = "${master_fqdn}" ] && continue
    ensure_replica_bound "${master_fqdn}" "${fqdn}" "${master_id}" "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" || return 1
  done
}

# Idempotent replica binding (round-2 review): visibility alone never
# skips. Absent -> add-node --cluster-slave. Present but wrong role/parent
# -> engine-native repair via CLUSTER REPLICATE on the pod itself (safe:
# the target owns no slots as a would-be replica; REPLICATE is refused by
# the engine if it did). Present and bound -> done.
ensure_replica_bound() {
  local via="${1}" fqdn="${2}" master_id="${3}" shard="${4}"
  local line flags parent out
  build_cli "${via}"
  line=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | grep -F "${fqdn}" | head -1)
  if [ -z "${line}" ]; then
    build_cluster_cli
    out=$("${_ccli[@]}" --cluster add-node "${fqdn}:${SERVICE_PORT}" "${via}:${SERVICE_PORT}" --cluster-slave --cluster-master-id "${master_id}" 2>&1) || {
      classify attach-add-node yes "add replica ${fqdn} to shard ${shard} failed (re-entry re-drives): ${out}"
      return 1
    }
    echo "attached ${fqdn} as replica of shard ${shard} (master ${master_id})."
    return 0
  fi
  flags=$(echo "${line}" | awk '{print $3}')
  parent=$(echo "${line}" | awk '{print $4}')
  if echo "${flags}" | grep -q slave && [ "${parent}" = "${master_id}" ]; then
    return 0
  fi
  # visible but wrong role or wrong parent: repair on the pod itself
  build_cli "${fqdn}"
  out=$("${_cli[@]}" CLUSTER REPLICATE "${master_id}" 2>&1) || {
    classify attach-replicate no "CLUSTER REPLICATE ${master_id} on ${fqdn} failed: ${out}"
    return 1
  }
  echo "repaired ${fqdn}: now replicating shard ${shard} master ${master_id}."
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

  local remaining_host="" shard_line shard fqdns first roster
  roster=$(each_shard_fqdn_list) || exit 1
  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    [ "${shard}" = "$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_')" ] && continue
    first=$(first_fqdn_of_list "${fqdns}")
    if [ "$(cluster_state_of "${first}")" = "ok" ]; then
      remaining_host="${first}"
      break
    fi
  done <<< "${roster}"
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
    # No master of this shard in the cluster view: deletion already began.
    # NOT an automatic success — fail/handshake residue of this shard may
    # linger in remaining node tables (r4 CT06). Purge + absence proof.
    echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} has no master in cluster view — verifying residue-free absence."
    purge_shard_from_cluster || exit 1
    echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} absent with no residue."
    exit 0
  fi

  # interrupted-migration repair also gates the drain: rebalance weight=0
  # cannot start (and zero-proof cannot be trusted) with open slots.
  if open_slots_present "${remaining_host}"; then
    repair_open_slots "${remaining_host}" || exit 1
  fi
  local own
  own=$(slots_owned_by "${remaining_host}" "${master_id}")
  if [ "${own}" -gt 0 ]; then
    # CONCURRENT SCALE-IN CONTRACT (round-2 external review): the drain
    # must zero-weight not only this shard's master but EVERY master that
    # currently owns 0 slots. Weight-1 defaults would rebalance slots INTO
    # (a) a zero-proven departing sibling awaiting purge — its reset guard
    # then refuses and forces a re-drain ping-pong — and (b) mid-join fresh
    # masters, whose slots must come from their own completion driver.
    # With this exclusion a leaver that reaches 0 slots STAYS at 0, so
    # concurrent multi-shard drains terminate instead of re-polluting each
    # other. 0-slot masters are engine-observable truth; "is departing" is
    # not, so this is the strongest gate available from CLUSTER NODES.
    local drain_nodes wline wid wown
    local weight_args=("--cluster-weight" "${master_id}=0")
    drain_nodes=$(cluster_nodes_of "${remaining_host}")
    if [ -z "${drain_nodes}" ]; then
      classify remove-drain yes "cannot read CLUSTER NODES from ${remaining_host} to build drain weights — deferring"
      exit 1
    fi
    while read -r wline; do
      wid=$(echo "${wline}" | awk '{print $1}')
      [ -z "${wid}" ] && continue
      [ "${wid}" = "${master_id}" ] && continue
      # a fail-flagged master must never be a receiver either: rebalance
      # would abort mid-migration trying to move slots to it
      if echo "${wline}" | awk '{print $3}' | grep -q fail; then
        weight_args+=("--cluster-weight" "${wid}=0")
        continue
      fi
      wown=$(slots_owned_by "${remaining_host}" "${wid}")
      case "${wown}" in ''|*[!0-9-]*) classify remove-drain yes "invalid owned-slot count '${wown}' for master ${wid} — deferring drain"; exit 1 ;; esac
      if [ "${wown}" -eq 0 ]; then
        weight_args+=("--cluster-weight" "${wid}=0")
      fi
    done <<< "$(echo "${drain_nodes}" | awk '$3 ~ /master/')"
    build_cluster_cli
    local reb_out
    reb_out=$("${_ccli[@]}" --cluster rebalance "${remaining_host}:${SERVICE_PORT}" "${weight_args[@]}" 2>&1) || {
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

  purge_shard_from_cluster || exit 1
  echo "shard ${CURRENT_SHARD_COMPONENT_SHORT_NAME} removed cleanly (drained, reset, forgotten, absence-proven)."
  exit 0
}

# Residue-free removal (r4 CT06 live evidence): --cluster del-node also
# SHUTDOWNs the deleted node; a KB-managed pod restarts with its old
# nodes.conf and re-handshakes back into the cluster before KB terminates
# it, leaving fail/handshake entries in remaining node tables. Sequence
# that cannot resurrect instead:
#   1. FLUSHALL + CLUSTER RESET HARD on each leaving pod (identity is
#      destroyed on the node itself; a restart cannot rejoin),
#   2. CLUSTER FORGET of the old ids on EVERY remaining node (node tables
#      are per-node; "Unknown node" = already forgotten),
#   3. positive absence proof from every remaining pod (no fqdn line, no
#      old-id line, any flags) before rc=0.
purge_shard_from_cluster() {
  local pattern="" fqdn
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$'); do
    pattern="${pattern:+${pattern}|}${fqdn}"
  done

  local remaining=() shard_line shard fqdns self_upper roster
  self_upper=$(echo "${CURRENT_SHARD_COMPONENT_SHORT_NAME}" | tr '[:lower:]-' '[:upper:]_')
  roster=$(each_shard_fqdn_list) || return 1
  while read -r shard_line; do
    shard="${shard_line%% *}"
    fqdns="${shard_line#* }"
    [ "${shard}" = "${self_upper}" ] && continue
    for fqdn in $(echo "${fqdns}" | tr ',' '\n' | grep -v '^$'); do
      # r9 CT12: in a multi-shard scale-in the roster env snapshot still
      # lists SIBLING shards leaving in the same operation. A roster host
      # whose DNS name no longer exists has departed — its node table
      # died with it, so FORGET and the absence proof on it are vacuous.
      # Only DNS-gone hosts are skipped; a resolvable-but-unreachable
      # host (pod restarting) still defers below, keeping the proof strict.
      if ! host_resolves "${fqdn}"; then
        echo "roster host ${fqdn} no longer resolves — departed concurrently; skipping as vantage."
        continue
      fi
      remaining+=("${fqdn}")
    done
  done <<< "${roster}"
  if [ "${#remaining[@]}" -eq 0 ]; then
    classify remove-no-receiver no "no live remaining pods in roster — refusing purge"
    return 1
  fi

  # old ids of this shard: UNION across every remaining pod's view (a
  # residue line can be visible from one pod only) plus each reachable
  # leaving pod's own MYID read BEFORE reset (id-only noaddr residue
  # carries no fqdn, so views alone can miss it).
  local nodes ids="" id host
  for host in "${remaining[@]}"; do
    build_cli "${host}"
    nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
    ids="${ids} $(echo "${nodes}" | grep -E "${pattern}" | awk '{print $1}')"
  done
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    build_cli "${fqdn}"
    if "${_cli[@]}" PING 2>/dev/null | grep -q PONG; then
      id=$("${_cli[@]}" CLUSTER MYID 2>/dev/null | tr -d '\r')
      [ -n "${id}" ] && ids="${ids} ${id}"
    fi
  done
  ids=$(echo "${ids}" | tr ' ' '\n' | grep -v '^$' | sort -u)

  # 1) neutralize reachable leaving pods: identity death, not shutdown.
  # Explicit RESET precondition (design contract): a leaving pod whose
  # own myself line still claims master+slots is never reset — that is
  # a drain failure, not a cleanup step.
  for fqdn in $(echo "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | sort); do
    build_cli "${fqdn}"
    if "${_cli[@]}" PING 2>/dev/null | grep -q PONG; then
      if self_claims_master_with_slots; then
        classify remove-slots-nonzero yes "${fqdn} still claims master with slots — refusing reset"
        return 1
      fi
      "${_cli[@]}" FLUSHALL >/dev/null 2>&1 || true  # replicas refuse (harmless); master proven slotless
      "${_cli[@]}" CLUSTER RESET HARD >/dev/null 2>&1 || {
        classify remove-reset yes "CLUSTER RESET HARD on ${fqdn} failed"
        return 1
      }
    fi
  done

  # 2) forget the old ids on every remaining node
  local out
  for host in "${remaining[@]}"; do
    build_cli "${host}"
    for id in ${ids}; do
      out=$("${_cli[@]}" CLUSTER FORGET "${id}" 2>&1) || true
      case "${out}" in
        OK*|*"Unknown node"*) ;;
        *) classify remove-forget yes "FORGET ${id} on ${host} failed: ${out}"; return 1 ;;
      esac
    done
  done

  # 3) positive absence proof from EVERY remaining pod
  local residue
  for host in "${remaining[@]}"; do
    build_cli "${host}"
    nodes=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r')
    residue=$(echo "${nodes}" | grep -E "${pattern}" || true)
    for id in ${ids}; do
      residue="${residue}$(echo "${nodes}" | awk -v i="${id}" '$1==i')"
    done
    if [ -n "${residue}" ]; then
      classify remove-residue yes "removed-shard residue still visible from ${host}"
      return 1
    fi
  done
  return 0
}

# DNS existence check for roster members. getent absent (minimal image)
# falls back to "resolvable" so behavior degrades to the strict defer
# path, never to a weaker proof.
host_resolves() {
  command -v getent >/dev/null 2>&1 || return 0
  getent hosts "${1}" >/dev/null 2>&1
}

# The current pod's own cluster view: does it claim to be a master that
# still owns slot ranges? (Engine truth read on the node itself; used as
# the explicit RESET precondition.) Caller must have built _cli first.
self_claims_master_with_slots() {
  local line
  line=$("${_cli[@]}" CLUSTER NODES 2>/dev/null | tr -d '\r' | awk '$3 ~ /myself/')
  [ -z "${line}" ] && return 1
  echo "${line}" | awk '{print $3}' | grep -q master || return 1
  [ -n "$(echo "${line}" | awk '{for(i=9;i<=NF;i++) printf "%s", $i}')" ]
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
