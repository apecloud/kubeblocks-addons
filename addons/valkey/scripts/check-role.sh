#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#   The script prints exactly one stdout payload that kbagent forwards as
#   the role string. Two output modes:
#
#   1. Sentinel-replication topology (SENTINEL_POD_FQDN_LIST set):
#      a) Sentinel reachable: emit a compact GlobalRoleSnapshot JSON.
#         The role bit (primary/secondary) comes from sentinel's view —
#         specifically the runid match between the local pod's
#         INFO server `run_id` and the sentinel-recorded master `runid`.
#         Sentinel is the role authority; local INFO replication is NOT
#         allowed to override sentinel's election in this path. This
#         closes the Bug B class: a demoted primary whose local INFO
#         still reports `role:master` will produce `roleName: secondary`
#         here because its run_id no longer matches the sentinel-elected
#         master's runid.
#      b) Sentinel unreachable: emit a plain string from local INFO
#         replication. The controller's #10269 plain-EventTime gate
#         prevents this fallback from overriding an authoritative
#         annotation, so a stale primary reporting plain `primary`
#         cannot displace the freshly-promoted primary's authoritative
#         JSON snapshot.
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

# fetch_sentinel_master_output captures the full `SENTINEL master <name>`
# output from the first reachable sentinel. The CLI returns an array of
# alternating key/value lines (key on one line, value on next). This is
# NOT a sentinel-quorum-agreed view — it is the first reachable sentinel's
# local opinion. That is acceptable for role authority: by the time
# sentinel completes a failover, every sentinel agrees on the master runid
# and config-epoch; transient disagreement during the failover window is
# exactly the case where we prefer "secondary" or fallback-plain over
# emitting an authoritative primary report.
#
# Bash builtins only — no pipeline children (zombie guard; same rule as
# the INFO replication parse).
fetch_sentinel_master_output() {
  local sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  local master_name="${VALKEY_COMPONENT_NAME:-${KB_CLUSTER_COMP_NAME:-valkey}}"
  local IFS=',' s_host cmd out
  read -ra sentinels <<<"${SENTINEL_POD_FQDN_LIST}"
  for s_host in "${sentinels[@]}"; do
    cmd="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h ${s_host} -p ${sentinel_port}"
    if ! is_empty "${SENTINEL_PASSWORD}"; then
      cmd="${cmd} -a ${SENTINEL_PASSWORD}"
    fi
    out=$(${cmd} sentinel master "${master_name}" 2>/dev/null) || continue
    if [ -n "${out}" ]; then
      printf '%s' "${out}"
      return 0
    fi
  done
  printf ''
  return 1
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
#   - <epoch> is the config-epoch reported by the first reachable
#     sentinel for the master. config-epoch increments per agreed
#     failover, so a stale report from a demoted primary never lexically
#     beats a fresh report from the new primary (both pods carry the
#     same config-epoch when sentinel reports it consistently; pods
#     reporting different config-epoch values resolve via lexical order).
#   - <short-replid> is the first 16 hex chars of the master replication
#     id (`master_replid` from local INFO replication). The replid rolls
#     forward on every promotion, so two distinct masters never share
#     the same prefix.
# When sentinel cannot supply config-epoch the epoch falls back to
# `master_repl_offset` which is monotonic per replid; ordering stays
# stable within one master's lifetime even during a temporary sentinel
# split. The term contains `:` so the controller staleness gate
# (PR #10269 fix) treats it as an authoritative version and refuses to
# be overridden by a plain per-pod EventTime number from a stale primary
# report. The controller currently uses the `:` discriminator for
# authoritative-vs-plain classification rather than full sentinel-epoch
# total ordering; lexical comparison gives correct results for the
# scenarios we ship today (same replid → monotonic offset, different
# replid → different short-replid prefix), and a future controller
# enhancement can do real numeric comparison of the epoch segment.
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
  sentinel_out=$(fetch_sentinel_master_output) || sentinel_out=""
  set_xtrace_when_ut_mode_false

  if ! is_empty "${sentinel_out}"; then
    # Sentinel reachable → derive the authoritative role from sentinel's
    # master runid. Local INFO replication is NOT permitted to override
    # sentinel's election here: a demoted primary whose local INFO still
    # reports role:master must surface as secondary so we never wrap a
    # stale local view as an authoritative GlobalRoleSnapshot.
    sentinel_runid=$(parse_sentinel_master_field "runid" "${sentinel_out}")
    sentinel_epoch=$(parse_sentinel_master_field "config-epoch" "${sentinel_out}")
    local_runid=$(query_local_run_id)

    if ! is_empty "${local_runid}" && [ "${local_runid}" = "${sentinel_runid}" ]; then
      role_name="primary"
    else
      role_name="secondary"
    fi

    build_global_role_snapshot "${role_name}" "${sentinel_epoch}" "${repl_info}"
  else
    # Sentinel unreachable → fall back to plain string from local INFO.
    # The controller's PR #10269 plain-EventTime gate blocks this output
    # from overriding an existing authoritative annotation, so a stale
    # primary cannot displace the freshly-promoted primary's snapshot.
    printf '%s' "${local_role}"
  fi
else
  # Standalone topology — no Bug B window, plain string is sufficient.
  printf '%s' "${local_role}"
fi
