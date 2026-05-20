#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#   The script prints exactly one stdout payload that kbagent forwards as
#   the role string. Two output modes:
#
#   1. Sentinel-replication topology (SENTINEL_POD_FQDN_LIST set):
#      a) Strict sentinel-runid majority reached: emit a compact
#         GlobalRoleSnapshot JSON. The role bit (primary/secondary)
#         comes from the runid match between the local pod's
#         INFO server `run_id` and the runid that a strict majority
#         (>= floor(N/2)+1) of sentinels agree is the current master.
#         Sentinel quorum is the role authority; local INFO replication
#         is NOT allowed to override sentinel's election. This closes
#         the Bug B class: a demoted primary whose local INFO still
#         reports `role:master` produces `roleName:secondary` here
#         because the quorum-agreed runid no longer matches its
#         run_id. A stale sentinel that still thinks the old master
#         is current does NOT have enough votes to become the quorum
#         answer, so the demoted primary cannot ride the stale
#         minority view into an authoritative primary JSON.
#      b) No sentinel quorum (all unreachable, single sentinel only,
#         or sentinels split on the master runid during a failover
#         convergence window): emit a plain string from local INFO
#         replication. The controller's PR #10269 plain-EventTime gate
#         prevents this fallback from overriding an authoritative
#         annotation, so a stale primary reporting plain `primary`
#         cannot displace the freshly-promoted primary's authoritative
#         JSON snapshot. We deliberately do NOT emit authoritative
#         `primary` JSON in this case — it is the very window where the
#         role bit cannot yet be trusted.
#
#   2. Standalone topology (no sentinel):
#      A plain `"primary"` / `"secondary"` string from local INFO
#      replication. Single-node deployments do not have the stale-event
#      flap class, so the existing plain output is preserved.
#
#   For Valkey (Redis-compatible):
#     INFO replication → role:master  → primary
#     INFO replication → role:slave   → secondary
#     INFO server      → run_id:<40-hex>  (stable per Valkey lifetime)
#     SENTINEL master <name> → key/value pairs including runid and
#                              config-epoch (alternating lines)
#
#   Using valkey-cli (not redis-cli) because Valkey ships its own CLI.
#   The -h 127.0.0.1 ensures we hit this pod's own server.
#
#   KB_SERVICE_PORT and KB_HOST_IP are injected by the roleProbe env[]
#   block in the ComponentDefinition (not from vars[]). KB_POD_NAME and
#   KB_POD_UID are also injected there so the JSON pair carries the live
#   pod identity (controller path drops pairs with mismatched podUid).
#
# This script is now pure read-and-emit — NO self-heal here:
#   - Cascade-topology repair lives in valkey-self-heal.sh, run as a
#     long-running daemon spawned by valkey-start.sh entrypoint, in the
#     valkey container. Single fork at container lifetime → no zombie
#     accumulation. PR #2615 cascade guards (skip-stale-role /
#     skip-self-target / remote-master-unreachable) live with the cascade
#     function in the daemon file.
#   - Full-sync stall detection (Bug 5) also lives in valkey-self-heal.sh
#     for the same reason (defense in depth: even though stall detection
#     is local-only and fast, keeping it out of the kbagent-driven probe
#     path eliminates ANY Pattern B exposure to roleProbe SIGKILL events;
#     see addon-probe-script-fork-and-zombie-guide.md).
#
# Same idiom as clickhouse / mariadb-galera / postgresql startup daemons.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"

build_cli_cmd() {
  local cmd="valkey-cli --no-auth-warning -h 127.0.0.1 -p ${port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  fi
  echo "${cmd}"
}

# is_sentinel_topology returns 0 when the deployment includes a Sentinel
# component (cross-component variables wired in CMPD). Standalone clusters
# do not set SENTINEL_POD_FQDN_LIST.
is_sentinel_topology() {
  ! is_empty "${SENTINEL_POD_FQDN_LIST}" && ! is_empty "${SENTINEL_COMPONENT_NAME}"
}

# parse_repl_field extracts a single CRLF-terminated `key:value` field from
# the captured `INFO replication` (or `INFO server`) output without spawning
# a pipeline. Empty output is returned when the key is missing.
parse_repl_field() {
  local key="$1" repl_info="$2" line value=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "${line}" in
      "${key}:"*) value="${line#${key}:}"; break ;;
    esac
  done <<<"${repl_info}"
  printf '%s' "${value}"
}

# parse_sentinel_master_field extracts a value from the SENTINEL master
# alternating key/value output. Returns empty when the key is missing.
parse_sentinel_master_field() {
  local key="$1" out="$2"
  local prev_line="" line value=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ "${prev_line}" = "${key}" ]; then
      value="${line}"
      break
    fi
    prev_line="${line}"
  done <<<"${out}"
  printf '%s' "${value}"
}

# query_sentinel_master_runid_quorum queries ALL sentinels in
# SENTINEL_POD_FQDN_LIST, votes on the master runid each one reports,
# and returns "<runid>:<config-epoch>" when a strict majority
# (>= floor(N/2)+1) agree on the same runid. Returns empty (exit 1)
# when no majority exists.
#
# The "first reachable sentinel" pattern is NOT used here: during a
# sentinel FAILOVER convergence window, a stale sentinel can still
# report the old master's runid while the rest of the quorum has moved
# to the new master. A roleProbe that trusts the first reachable
# sentinel would then wrap that stale view as an authoritative
# GlobalRoleSnapshot pair, bypassing the controller's PR #10269 plain-
# EventTime gate. The strict-majority pattern matches the bar already
# set by valkey-start.sh:query_sentinel_quorum_for_master (used for
# REPLICAOF source selection at startup) and the sentinel-isolation
# guard in valkey-member-leave.sh.
#
# Vote key is runid alone (not the runid+epoch tuple) because runid is
# the identity of the master process; config-epoch is metadata for
# term ordering and is taken from the highest reported value among
# voters for the winning runid. A 3-way split (each sentinel reports a
# different runid) yields no majority and falls back to the plain-
# string path on the caller side.
#
# Bash builtins only — no pipeline children (zombie guard; same rule
# as the INFO replication parse).
query_sentinel_master_runid_quorum() {
  local sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  local master_name="${VALKEY_COMPONENT_NAME:-${KB_CLUSTER_COMP_NAME:-valkey}}"

  local sentinel_cli_base="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p ${sentinel_port}"
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    sentinel_cli_base="${sentinel_cli_base} -a ${SENTINEL_PASSWORD}"
  fi

  local -a sentinels=()
  IFS=',' read -ra sentinels <<<"${SENTINEL_POD_FQDN_LIST}"
  local total="${#sentinels[@]}"
  [ "${total}" -eq 0 ] && { printf ''; return 1; }
  local quorum=$(( total / 2 + 1 ))

  # Parallel-array vote tally. vote_runids[i] keyed against
  # vote_counts[i] and vote_epochs[i] for the same i.
  local -a vote_runids=()
  local -a vote_counts=()
  local -a vote_epochs=()

  local s_fqdn cmd out runid epoch found i
  for s_fqdn in "${sentinels[@]}"; do
    cmd="${sentinel_cli_base} -h ${s_fqdn}"
    out=$(${cmd} sentinel master "${master_name}" 2>/dev/null) || continue
    is_empty "${out}" && continue

    runid=$(parse_sentinel_master_field "runid" "${out}")
    epoch=$(parse_sentinel_master_field "config-epoch" "${out}")
    is_empty "${runid}" && continue

    found=0
    for i in "${!vote_runids[@]}"; do
      if [ "${vote_runids[$i]}" = "${runid}" ]; then
        vote_counts[$i]=$(( vote_counts[$i] + 1 ))
        # Track highest epoch among voters for this runid. Numeric
        # comparison guarded for empty values (sentinel may omit
        # config-epoch in degraded states).
        if [ -n "${epoch}" ] && \
           { [ -z "${vote_epochs[$i]}" ] || \
             { [[ "${epoch}" =~ ^[0-9]+$ ]] && \
               [[ "${vote_epochs[$i]}" =~ ^[0-9]+$ ]] && \
               [ "${epoch}" -gt "${vote_epochs[$i]}" ]; }; }; then
          vote_epochs[$i]="${epoch}"
        fi
        found=1
        break
      fi
    done
    if [ "${found}" -eq 0 ]; then
      vote_runids+=("${runid}")
      vote_counts+=(1)
      vote_epochs+=("${epoch}")
    fi
  done

  local winner_runid="" winner_count=0 winner_epoch=""
  for i in "${!vote_runids[@]}"; do
    if [ "${vote_counts[$i]}" -gt "${winner_count}" ]; then
      winner_runid="${vote_runids[$i]}"
      winner_count="${vote_counts[$i]}"
      winner_epoch="${vote_epochs[$i]}"
    fi
  done

  if [ "${winner_count}" -ge "${quorum}" ]; then
    printf '%s:%s' "${winner_runid}" "${winner_epoch}"
    return 0
  fi

  printf ''
  return 1
}

# query_local_run_id returns the local Valkey instance's run_id from
# INFO server. Empty string on failure. run_id is unique per Valkey
# process lifetime and is what sentinel records when it elects a master.
query_local_run_id() {
  local server_info
  server_info=$(${cli_cmd} info server 2>/dev/null) || return 0
  parse_repl_field "run_id" "${server_info}"
}

# build_global_role_snapshot emits the GlobalRoleSnapshot JSON consumed by
# the KB controller's authoritative-snapshot path. The term layout is:
#   sentinel-epoch:<epoch>:replid:<short-replid>
# where:
#   - <epoch> is the config-epoch agreed by a strict majority of
#     sentinels (from query_sentinel_master_runid_quorum). When sentinel
#     omits config-epoch the fallback is `master_repl_offset` from local
#     INFO replication.
#   - <short-replid> is the first 16 hex chars of the master replication
#     id (`master_replid` from local INFO replication). The replid rolls
#     forward on every promotion, so two distinct masters do not share
#     the same prefix.
#
# The term contains `:` so the controller staleness gate (PR #10269 fix)
# treats it as an authoritative version and does not overwrite it with a
# plain per-pod EventTime number from a later stale primary report. The
# controller currently uses the `:` only as an authoritative-vs-plain
# discriminator; it does NOT yet do numeric comparison of the
# sentinel-epoch segment. A future controller enhancement can add real
# numeric ordering, at which point this term layout is forward-compatible
# (the epoch is the leading numeric field).
build_global_role_snapshot() {
  local role_name="$1" epoch="$2" repl_info="$3"
  local pod_name="${KB_POD_NAME:-${HOSTNAME:-unknown}}"
  local pod_uid="${KB_POD_UID:-}"
  local replid short_replid

  replid=$(parse_repl_field "master_replid" "${repl_info}")
  is_empty "${replid}" && replid="unknown"
  short_replid="${replid:0:16}"

  if is_empty "${epoch}"; then
    epoch=$(parse_repl_field "master_repl_offset" "${repl_info}")
  fi
  is_empty "${epoch}" && epoch="0"

  local term="sentinel-epoch:${epoch}:replid:${short_replid}"
  # Compact JSON, no newlines. printf %s avoids the trailing \n that echo
  # would add — the controller json.Unmarshal tolerates trailing \n but
  # downstream consumers may surface the value as a label, where \n is
  # rejected by Kubernetes label validation.
  printf '%s' "{\"term\":\"${term}\",\"PodRoleNamePairs\":[{\"podName\":\"${pod_name}\",\"roleName\":\"${role_name}\",\"podUid\":\"${pod_uid}\"}]}"
}

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library

cli_cmd=$(build_cli_cmd)

unset_xtrace_when_ut_mode_false
# Capture the full INFO replication output once via a single command
# substitution (one valkey-cli child process), then parse it with bash
# builtins. Pipelines like `... | grep | tr` would spawn additional
# children (one per stage). When kbagent SIGKILLs this script for
# exceeding probe timeoutSeconds, those pipeline children become
# orphans and are reparented to kbagent's PID 1, which is a Go binary
# that does not reap unrelated children — they accumulate as zombies.
# Refer to docs/addon-probe-script-fork-and-zombie-guide.md.
#
# valkey-cli INFO output uses CRLF line endings per the Redis protocol;
# the parameter expansion `${line%$'\r'}` trims the trailing CR before
# the case match.
repl_info=$(${cli_cmd} info replication 2>/dev/null) || repl_info=""
role_line=""
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "${line}" in
    role:*) role_line="${line}"; break ;;
  esac
done <<<"${repl_info}"
set_xtrace_when_ut_mode_false

# Parse the local-observed role from INFO replication. This is ONLY used
# directly in standalone mode or as the sentinel-unreachable fallback;
# in the sentinel-reachable path the role bit is overridden by the
# sentinel runid comparison below.
case "${role_line}" in
  "role:master") local_role="primary"   ;;
  "role:slave")  local_role="secondary" ;;
  *)
    echo "unknown role: '${role_line}'" >&2
    # Returning a non-zero exit code tells KubeBlocks the probe failed.
    # KubeBlocks will increment the failure counter and, after
    # failureThreshold is exceeded, clear the role label on this pod.
    exit 1
    ;;
esac

if is_sentinel_topology; then
  unset_xtrace_when_ut_mode_false
  quorum_view=$(query_sentinel_master_runid_quorum) || quorum_view=""
  set_xtrace_when_ut_mode_false

  if ! is_empty "${quorum_view}"; then
    # Strict-majority sentinel agreement → emit authoritative JSON.
    # Local INFO replication is NOT permitted to override sentinel's
    # election here: a demoted primary whose local INFO still reports
    # role:master must surface as secondary so we never wrap a stale
    # local view as an authoritative GlobalRoleSnapshot pair.
    sentinel_runid="${quorum_view%%:*}"
    sentinel_epoch="${quorum_view#*:}"
    local_runid=$(query_local_run_id)

    if ! is_empty "${local_runid}" && [ "${local_runid}" = "${sentinel_runid}" ]; then
      role_name="primary"
    else
      role_name="secondary"
    fi

    build_global_role_snapshot "${role_name}" "${sentinel_epoch}" "${repl_info}"
  else
    # No sentinel quorum (all sentinels unreachable, single sentinel
    # reachable out of 3+, or sentinels split on the master runid
    # mid-failover) → fall back to plain string from local INFO. The
    # controller's PR #10269 plain-EventTime gate blocks this output
    # from overriding an existing authoritative annotation, so a stale
    # primary cannot displace the freshly-promoted primary's snapshot
    # even on this path. We do NOT emit authoritative `primary` JSON
    # when sentinel quorum is missing — that is precisely the
    # convergence window where the role bit cannot be trusted.
    printf '%s' "${local_role}"
  fi
else
  # Standalone topology — no Bug B window, plain string is sufficient.
  printf '%s' "${local_role}"
fi
