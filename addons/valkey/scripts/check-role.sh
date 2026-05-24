#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#   The contract is simple: print exactly one line to stdout — the role name
#   that matches one of the roles[] entries in ComponentDefinition.
#
#   For Valkey (Redis-compatible):
#     INFO replication → role:master  →  print "primary"
#     INFO replication → role:slave   →  print "secondary"
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

# Engine-authoritative role version (kb-role-version) — sentinel config-epoch.
# Contract: KubeBlocks controllers (post-PR #10280) use the second line
# `kb-role-version=<uint64>` to gate stale roleProbe events; the value MUST
# come from an engine epoch that is monotonic and comparable across pods in
# the component. For Valkey + sentinel, the sentinel `config-epoch` on the
# current master bumps on every successful sentinel-driven failover (both
# auto failover and `SENTINEL FAILOVER` triggered via switchover.sh), which
# is exactly the granularity Bug B's stale-event gate needs.
#
# Resilience: silently fall back to legacy single-line output if sentinel is
# unreachable, the password is missing, or the parsed value is non-numeric.
# Per PR #10280 strict-parser contract, emitting a malformed line would make
# the controller reject the event outright; emitting NO version line keeps
# the legacy EventTime fallback path. Single valkey-cli invocation, no
# pipelines, to preserve the fork-and-zombie discipline (see
# docs/addon-probe-script-fork-and-zombie-guide.md).
engine_version=""
if [ -n "${SENTINEL_PASSWORD:-}" ] && [ -n "${SENTINEL_POD_FQDN_LIST:-}" ]; then
  sentinel_host="${SENTINEL_POD_FQDN_LIST%%,*}"
  sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  sentinel_out=$(valkey-cli --no-auth-warning -h "${sentinel_host}" -p "${sentinel_port}" -a "${SENTINEL_PASSWORD}" sentinel masters 2>/dev/null) || sentinel_out=""
  ce_marker=""
  while IFS= read -r sline; do
    sline="${sline%$'\r'}"
    if [ -n "${ce_marker}" ]; then
      engine_version="${sline}"
      break
    fi
    [ "${sline}" = "config-epoch" ] && ce_marker="1"
  done <<<"${sentinel_out}"
fi
set_xtrace_when_ut_mode_false

# printf %s avoids the trailing newline that `echo` adds — KubeBlocks roleProbe
# rejects label values containing '\n' (Kubernetes label validation), surfacing
# as transient `RoleProbeNotDone` and `invalid label value primary\n` events.
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

# Append engine-authoritative version on second line only when sentinel
# returned a clean uint64. Non-numeric or empty result drops back to legacy.
case "${engine_version}" in
  ''|*[!0-9]*) : ;;
  *) printf '\nkb-role-version=%s' "${engine_version}" ;;
esac
