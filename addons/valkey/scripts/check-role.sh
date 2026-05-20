#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#   The script prints exactly one stdout payload that kbagent forwards as
#   the role string. Two output modes:
#
#   1. Sentinel-replication topology (SENTINEL_POD_FQDN_LIST set):
#      A compact GlobalRoleSnapshot JSON with a per-pod role pair and a
#      monotonic `term`. The controller's parseGlobalRoleSnapshot accepts
#      this JSON and uses `term` as the authoritative snapshot version,
#      which prevents stale plain-EventTime probe events from flipping the
#      exclusive role label after a sentinel failover.
#
#   2. Standalone topology (no sentinel):
#      A plain `"primary"` (master replication line) string. Single-node
#      deployments do not have the stale-event flap class, so the existing
#      plain output is preserved.
#
#   For Valkey (Redis-compatible):
#     INFO replication → role:master  → primary
#     INFO replication → role:slave   → secondary
#
#   Using valkey-cli (not redis-cli) because Valkey ships its own CLI.
#   The -h 127.0.0.1 ensures we hit this pod's own server.
#
#   KB_SERVICE_PORT and KB_HOST_IP are injected by the roleProbe env[] block
#   in the ComponentDefinition (not from vars[]).
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
# the captured `INFO replication` output without spawning a pipeline. Empty
# output is returned when the key is missing.
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

# query_sentinel_config_epoch queries any reachable sentinel for the master
# config-epoch. The config-epoch is sentinel's authoritative election term
# and increments monotonically per agreed failover, so it is the proper
# ordering source for KubeBlocks' GlobalRoleSnapshot.term comparison.
# Returns empty string on failure (no sentinel reachable, missing field).
query_sentinel_config_epoch() {
  local sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  local master_name="${VALKEY_COMPONENT_NAME:-${KB_CLUSTER_COMP_NAME:-valkey}}"
  local IFS=',' s_host cmd out epoch=""
  read -ra sentinels <<<"${SENTINEL_POD_FQDN_LIST}"
  for s_host in "${sentinels[@]}"; do
    cmd="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h ${s_host} -p ${sentinel_port}"
    if ! is_empty "${SENTINEL_PASSWORD}"; then
      cmd="${cmd} -a ${SENTINEL_PASSWORD}"
    fi
    # `SENTINEL master <name>` returns a 2-line-per-field list (key on
    # one line, value on next). Capture once; parse with bash builtins
    # so probe SIGKILL does not orphan pipeline children (zombie guard,
    # same rule as the INFO replication parse above).
    out=$(${cmd} sentinel master "${master_name}" 2>/dev/null) || continue
    local prev_line="" line
    while IFS= read -r line; do
      line="${line%$'\r'}"
      if [ "${prev_line}" = "config-epoch" ]; then
        epoch="${line}"
        break
      fi
      prev_line="${line}"
    done <<<"${out}"
    [ -n "${epoch}" ] && break
  done
  printf '%s' "${epoch}"
}

# build_global_role_snapshot emits the GlobalRoleSnapshot JSON consumed by
# the KB controller's authoritative-snapshot path. The term layout is:
#   sentinel-epoch:<epoch>:replid:<short-replid>
# where:
#   - <epoch> is the sentinel-quorum-agreed config-epoch for the master.
#     It increments per failover so a stale report from a demoted primary
#     never lexically beats a fresh report from the new primary.
#   - <short-replid> is the first 16 hex chars of the master replication id
#     (`master_replid` from INFO replication). The replid rolls forward on
#     every promotion, so two distinct masters never share the same prefix.
# When sentinel is unreachable the epoch falls back to `master_repl_offset`
# which is monotonic per replid, so ordering is still stable within one
# master's lifetime even during a temporary sentinel split.
# The term contains `:` so the controller staleness gate (PR #10269 fix)
# treats it as an authoritative version and refuses to be overridden by a
# plain per-pod EventTime number from a stale primary report.
build_global_role_snapshot() {
  local role_name="$1" repl_info="$2"
  local pod_name="${KB_POD_NAME:-${HOSTNAME:-unknown}}"
  local pod_uid="${KB_POD_UID:-}"
  local epoch replid short_replid

  replid=$(parse_repl_field "master_replid" "${repl_info}")
  is_empty "${replid}" && replid="unknown"
  short_replid="${replid:0:16}"

  epoch=$(query_sentinel_config_epoch)
  # Fall back to master_repl_offset when sentinel cannot be reached. The
  # offset is monotonic per master lifetime, which preserves ordering
  # within one master but does not cross failover boundaries. Combined
  # with the replid prefix the term still distinguishes two masters; the
  # controller only needs lexical ordering against pods on the same
  # replid to enforce the exclusive-role gate.
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

# printf %s avoids the trailing newline that `echo` adds — KubeBlocks roleProbe
# rejects label values containing '\n' (Kubernetes label validation), surfacing
# as transient `RoleProbeNotDone` and `invalid label value primary\n` events.
case "${role_line}" in
  "role:master") role_name="primary"   ;;
  "role:slave")  role_name="secondary" ;;
  *)
    echo "unknown role: '${role_line}'" >&2
    # Returning a non-zero exit code tells KubeBlocks the probe failed.
    # KubeBlocks will increment the failure counter and, after
    # failureThreshold is exceeded, clear the role label on this pod.
    exit 1
    ;;
esac

# In sentinel-replication topology, emit a GlobalRoleSnapshot JSON so the
# controller treats this probe report as authoritative (not a plain
# per-pod role). Standalone deployments keep the plain string output.
if is_sentinel_topology; then
  build_global_role_snapshot "${role_name}" "${repl_info}"
else
  printf '%s' "${role_name}"
fi
