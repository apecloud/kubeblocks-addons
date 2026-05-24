#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#   Contract (post-PR apecloud/kubeblocks#10280): stdout is parsed via
#   `strings.Fields`. The first whitespace-separated token must be the role
#   name (one of the roles[] entries in ComponentDefinition); an optional
#   second whitespace-separated token carries an engine-authoritative
#   `uint64` role version that the controller's staleness gate uses to
#   reject replayed Kubernetes Event objects. Any other shape is rejected.
#   Only the first token becomes the Pod role label.
#
#   For Valkey (Redis-compatible):
#     INFO replication → role:master  →  print "primary"  (first token)
#     INFO replication → role:slave   →  print "secondary" (first token)
#   Then, when reachable, the highest sentinel config-epoch is appended as
#   the second token, separated by a newline.
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

# Engine-authoritative role version — sentinel config-epoch.
# Contract: KubeBlocks controllers (post-PR #10280) parse roleProbe stdout
# as whitespace-separated tokens; a second token must be a clean uint64,
# otherwise the entire event is rejected as malformed (no silent fallback
# to EventTime). The version MUST come from an engine epoch that is
# monotonic and comparable across pods in the component. For Valkey +
# sentinel, the sentinel `config-epoch` on the current master bumps on
# every successful sentinel-driven failover (both auto failover and
# `SENTINEL FAILOVER` triggered via switchover.sh), which is exactly the
# granularity Bug B's stale-event gate needs.
#
# Resilience: pick the highest `config-epoch` across reachable sentinels
# (matches the pattern in valkey-member-leave.sh). A partially reachable
# sentinel set is normal during failover or network partition; selecting a
# stale/isolated sentinel would emit a stale version and starve subsequent
# legitimate updates because the controller stores the engine annotation
# and refuses legacy fallback once it has been recorded.
#
# Silently fall back to legacy single-line output when no sentinel is
# reachable, the password is missing, or no parsed value is a clean uint64.
# Single valkey-cli invocation per sentinel attempt, no pipelines, to
# preserve the fork-and-zombie discipline (see
# docs/addon-probe-script-fork-and-zombie-guide.md).
engine_version=""
if [ -n "${SENTINEL_PASSWORD:-}" ] && [ -n "${SENTINEL_POD_FQDN_LIST:-}" ]; then
  sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  # TLS args must flow into the sentinel query path; silently dropping them
  # on a TLS-enabled topology would make every sentinel call fail and the
  # whole script degrade to legacy single-line output. Match the pattern in
  # valkey-member-leave.sh / valkey-start.sh: append ${VALKEY_CLI_TLS_ARGS}
  # whenever it is set.
  sentinel_tls_args="${VALKEY_CLI_TLS_ARGS:-}"
  best_epoch=-1
  IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
  for s in "${sentinel_fqdns[@]}"; do
    sentinel_out=$(valkey-cli --no-auth-warning -h "${s}" -p "${sentinel_port}" -a "${SENTINEL_PASSWORD}" ${sentinel_tls_args} sentinel masters 2>/dev/null) || continue
    ce_marker=""
    epoch=""
    while IFS= read -r sline; do
      sline="${sline%$'\r'}"
      if [ -n "${ce_marker}" ]; then
        epoch="${sline}"
        break
      fi
      [ "${sline}" = "config-epoch" ] && ce_marker="1"
    done <<<"${sentinel_out}"
    case "${epoch}" in
      ''|*[!0-9]*) continue ;;
    esac
    if [ "${epoch}" -gt "${best_epoch}" ]; then
      best_epoch="${epoch}"
      engine_version="${epoch}"
    fi
  done
fi
set_xtrace_when_ut_mode_false

# printf %s prints the role token with no trailing newline, so when no
# engine version is appended the stdout stays a single token. When the
# engine version IS appended below, it follows on a new line; the
# controller `strings.Fields` parser splits role and version into two
# tokens and uses only the role token as the Pod label, so embedded
# newlines no longer fail Kubernetes label validation.
case "${role_line}" in
  "role:master") printf %s "primary"   ;;
  "role:slave")  printf %s "secondary" ;;
  *)
    echo "unknown role: '${role_line}'" >&2
    # Returning a non-zero exit code tells KubeBlocks the probe failed.
    # KubeBlocks will increment the failure counter and, after
    # failureThreshold is exceeded, clear the role label on this pod.
    exit 1
    ;;
esac

# Append the engine-authoritative version as a second whitespace-separated
# token only when at least one reachable sentinel returned a clean uint64
# config-epoch. Empty or non-numeric falls back to legacy single-line and
# the controller uses its existing EventTime gate.
case "${engine_version}" in
  ''|*[!0-9]*) : ;;
  *) printf '\n%s' "${engine_version}" ;;
esac
