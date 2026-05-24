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
#     - When Sentinel returns a clean uint64 `config-epoch` AND a non-
#       empty hex master `runid`: the role token comes from a Sentinel-
#       authoritative gate, not from local INFO alone. `primary` is
#       emitted ONLY when local INFO=master AND local `INFO server`
#       `run_id` equals the Sentinel master `runid`. Otherwise emit
#       `secondary`. The matched Sentinel's `config-epoch` is appended
#       as the whitespace-separated second token. Local INFO=master on
#       a deposed primary is treated as `secondary` so two pods cannot
#       both emit `primary <same-epoch>` after a sentinel-driven
#       failover.
#     - When Sentinel is unreachable / the password is missing / the
#       parsed epoch is non-numeric / the parsed runid is empty or
#       malformed: fall back to legacy single-token output (local INFO
#       → `primary` for `role:master`, `secondary` for `role:slave`).
#       The controller then uses its existing EventTime gate.
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

# Local server identity. After a sentinel-driven failover the deposed
# primary still reports `role:master` locally for a brief window before its
# `replicaof <new-master>` lands; emitting `primary` from that pod would
# clash with the real new primary because both pods would carry the same
# sentinel config-epoch as their version. The local `run_id` (`INFO
# server`) is the stable per-server identity Sentinel records as `runid`
# for the current master. Comparing the two lets the script reject the
# stale-master self-report before it reaches the controller.
server_info=$(${cli_cmd} info server 2>/dev/null) || server_info=""
local_run_id=""
while IFS= read -r line; do
  line="${line%$'\r'}"
  case "${line}" in
    run_id:*) local_run_id="${line#run_id:}"; break ;;
  esac
done <<<"${server_info}"

# Engine-authoritative role and version from Sentinel.
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
# Authority: the role token must also come from Sentinel — local `INFO
# replication role:master` is not authoritative during the failover
# window. Treat this Pod as the real primary only when local INFO says
# `master` AND the local `run_id` equals the Sentinel master `runid`.
# Otherwise emit `secondary <epoch>` so the controller-side staleness
# gate sees a consistent global view. If Sentinel returns an empty /
# malformed `runid` we fall back to legacy single-token output rather
# than wrap incomplete authority into `primary`.
#
# Resilience: pick the highest `config-epoch` across reachable sentinels
# (matches the pattern in valkey-member-leave.sh) and capture that
# Sentinel's master `runid` from the same response. A partially reachable
# sentinel set is normal during failover; selecting a stale/isolated
# sentinel would emit a stale version and starve subsequent legitimate
# updates because the controller stores the engine annotation and refuses
# legacy fallback once recorded.
#
# Silently fall back to legacy single-token output when no sentinel is
# reachable, the password is missing, or no parsed value yields a clean
# uint64 epoch with a non-empty master runid. Single valkey-cli invocation
# per sentinel attempt, no pipelines, to preserve the fork-and-zombie
# discipline (see docs/addon-probe-script-fork-and-zombie-guide.md).
engine_version=""
sentinel_master_runid=""
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
    runid_marker=""
    epoch=""
    runid=""
    while IFS= read -r sline; do
      sline="${sline%$'\r'}"
      if [ -n "${ce_marker}" ]; then
        epoch="${sline}"
        ce_marker=""
      elif [ -n "${runid_marker}" ]; then
        runid="${sline}"
        runid_marker=""
      else
        case "${sline}" in
          "config-epoch") ce_marker="1" ;;
          "runid")        runid_marker="1" ;;
        esac
      fi
      [ -n "${epoch}" ] && [ -n "${runid}" ] && break
    done <<<"${sentinel_out}"
    case "${epoch}" in
      ''|*[!0-9]*) continue ;;
    esac
    # Sentinel runid must be a non-empty hex token. Anything else is a
    # malformed authority — wrapping it into `primary <epoch>` (or even
    # `secondary <epoch>` against a malformed peer) would re-create the
    # round-3 dual-primary race the gate is supposed to close. The shape
    # guard is purely on the character set; we don't pin length so the
    # check stays resilient if Valkey/Sentinel ever changes the runid
    # encoding.
    case "${runid}" in
      ''|*[!0-9a-fA-F]*) continue ;;
    esac
    if [ "${epoch}" -gt "${best_epoch}" ]; then
      best_epoch="${epoch}"
      engine_version="${epoch}"
      sentinel_master_runid="${runid}"
    fi
  done
fi
set_xtrace_when_ut_mode_false

# Resolve the authoritative role token by combining local INFO with the
# Sentinel master `runid`. If Sentinel data is unavailable the script
# stays on the legacy single-token path below and the controller falls
# back to EventTime. If Sentinel returned an epoch but the master `runid`
# is empty / malformed, we also drop back to legacy: emitting
# `primary <epoch>` with incomplete authority would re-create the
# round-3 dual-primary race that exposed Bug B in #10280 V1.
authoritative_role=""
if [ -n "${engine_version}" ] && [ -n "${sentinel_master_runid}" ]; then
  case "${role_line}" in
    "role:master")
      if [ -n "${local_run_id}" ] && [ "${local_run_id}" = "${sentinel_master_runid}" ]; then
        authoritative_role="primary"
      else
        # Local INFO still says master but Sentinel disagrees on identity:
        # this Pod is a deposed/stale primary, not the elected master.
        authoritative_role="secondary"
      fi
      ;;
    "role:slave")
      authoritative_role="secondary"
      ;;
    *)
      echo "unknown role: '${role_line}'" >&2
      exit 1
      ;;
  esac
fi

# printf %s prints the role token with no trailing newline, so when no
# engine version is appended the stdout stays a single token. When the
# engine version IS appended below, it follows on a new line; the
# controller `strings.Fields` parser splits role and version into two
# tokens and uses only the role token as the Pod label, so embedded
# newlines no longer fail Kubernetes label validation.
if [ -n "${authoritative_role}" ]; then
  printf %s "${authoritative_role}"
  printf '\n%s' "${engine_version}"
else
  # Legacy single-token output (Sentinel unreachable / empty runid /
  # non-numeric epoch). Use local INFO directly.
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
fi
