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
#     - When Sentinel is not configured (SENTINEL_POD_FQDN_LIST empty):
#       fall back to legacy single-token output (local INFO →
#       `primary` for `role:master`, `secondary` for `role:slave`).
#       The controller then uses its existing EventTime gate.
#     - When Sentinel is configured but quorum is transiently invalid
#       (insufficient valid sentinels / split view / missing password
#       causing NOAUTH / non-numeric epoch / empty or malformed runid):
#       only trust a local `role:slave` demotion. Local `role:master`
#       cannot prove primary without Sentinel majority, so fail the
#       current probe without emitting a role token. KubeBlocks consumes
#       a non-zero roleProbe event as "skip this sample", keeping the last
#       trusted role label instead of accepting a possibly stale master
#       self-report.
#     - Bootstrap exception: before postProvision registers the initial
#       master, reachable Sentinels can legitimately return no master
#       records. That is not a steady-state quorum failure. In that
#       specific case, fall back to local INFO so the first local master
#       can receive `primary` and postProvision can run.
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

# Engine-authoritative role and version via Sentinel quorum.
# Contract (post-PR #10280): the controller parses roleProbe stdout with
# `strings.Fields` and accepts either `<role>` or `<role> <uint64>`. The
# stale gate stores the accepted version in the Pod annotation and rejects
# any same-or-older event afterwards.
#
# Round-3 evidence (V1 against PR #10280 head 16803efa) showed that during
# a sentinel-driven failover, sentinels briefly disagree at the SAME
# `config-epoch`: one sentinel still reports the old master, another the
# new master with the runid not yet filled, etc. Picking a single sentinel
# in this window would emit a wrong `<role> <epoch>`, the controller would
# stamp the Pod annotation to that engine version, and subsequent correct
# events at the same epoch would all be rejected as stale.
#
# Quorum rule (Edward+Bob2 contract, signed off 2026-05-24):
#   - `configured_sentinel_count` = number of non-empty entries in
#     `SENTINEL_POD_FQDN_LIST`.
#   - `min_valid = configured_sentinel_count / 2 + 1` (strict majority of
#     configured, NOT of reachable — otherwise a single reachable sentinel
#     could self-certify).
#   - For each reachable sentinel, parse the master `(epoch, runid, flags)`
#     triple. Drop the entry when:
#       - `epoch` is not a clean uint64;
#       - `runid` is empty or contains a non-hex character;
#       - `flags` contains any transient/failure marker
#         (`failover_in_progress`, `force_failover`, `s_down`, `o_down`).
#   - If fewer than `min_valid` valid entries remain, OR the valid entries
#     fall into more than one `(epoch, runid)` group, local `role:master`
#     fails the current probe sample without emitting a role token, while
#     local `role:slave` emits `secondary`. The controller skips failed
#     roleProbe samples and keeps the previous Pod role label, so once
#     sentinels converge the next successful emission can take effect.
#   - Bootstrap-only exception: if at least one configured Sentinel
#     answers successfully but NONE of the successful answers contains a
#     master record yet, treat this as `bootstrap_no_sentinel_master` and
#     use local INFO. This only covers first-start registration. Failed
#     Sentinel queries, NOAUTH, malformed master records, and split views
#     do not enter this exception.
#   - When all valid entries agree on a single `(epoch, runid)` group AND
#     there are at least `min_valid` of them, that group is the quorum
#     authority. The version token is the group's epoch; the role token
#     is decided purely by comparing the group's `runid` to the local
#     `INFO server` `run_id`: match → `primary`, mismatch → `secondary`.
#     Local `INFO replication role:master` is intentionally NOT used as
#     an input to the versioned role decision.
#
# Single `valkey-cli ... sentinel masters` invocation per sentinel attempt,
# no pipelines, to preserve the fork-and-zombie discipline (see
# docs/addon-probe-script-fork-and-zombie-guide.md).
#
# Diagnostic instrumentation: when VALKEY_CHECK_ROLE_DEBUG=1, each call
# appends one JSON-shaped line to /tmp/check-role-debug.log inside the
# Pod with per-sentinel raw values, filter decisions, quorum result, and
# the emitted token. Stdout is NEVER written by this path — production
# contract (single role token, optionally followed by `\n<uint64>`) is
# preserved unchanged. Default off so production has zero overhead.
__check_role_debug_log=""
if [ "${VALKEY_CHECK_ROLE_DEBUG:-0}" = "1" ]; then
  __check_role_debug_log="/tmp/check-role-debug.log"
fi
__debug_records=""
__debug_sep=""
__debug_append() {
  # Build the per-sentinel JSON array element on a single line so the
  # final record stays JSONL-parseable. Comma-separate elements; the
  # first append uses an empty separator, every subsequent one uses ",".
  [ -z "${__check_role_debug_log}" ] && return 0
  __debug_records="${__debug_records}${__debug_sep}${1}"
  __debug_sep=","
}
__sentinel_records=""
engine_version=""
sentinel_master_runid=""
__quorum_decision_reason=""
__quorum_emit_role=""
if [ -n "${SENTINEL_POD_FQDN_LIST:-}" ]; then
  # Sentinel topology is detected by FQDN list alone. Password is only
  # an auth flag for the sentinel-cli call; missing password does NOT
  # mean "no Sentinel". Treating a missing password as `no_sentinel_env`
  # would re-open the cross-mode legacy `primary` fallback that this
  # whole quorum path exists to block (see fallback branches below).
  sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  # TLS args must flow into the sentinel query path; silently dropping
  # them on a TLS-enabled topology would make every sentinel call fail
  # and the whole script degrade to legacy single-line output. Match
  # the pattern in valkey-member-leave.sh / valkey-start.sh: append
  # ${VALKEY_CLI_TLS_ARGS} whenever it is set.
  sentinel_tls_args="${VALKEY_CLI_TLS_ARGS:-}"
  # Auth flag is conditional: only add -a when the password is set.
  # When password is missing on a sentinel-configured topology, the
  # cli call will fail (NOAUTH) and the per-sentinel drop will push
  # the decision to `insufficient_valid`, which the fallback branch now
  # correctly maps to a failed probe sample.
  sentinel_auth_args=""
  if [ -n "${SENTINEL_PASSWORD:-}" ]; then
    sentinel_auth_args="-a ${SENTINEL_PASSWORD}"
  fi
  # Configured total: count non-empty entries. Empty entries from a
  # trailing comma or runtime mis-render must not lower the quorum bar.
  IFS=',' read -ra sentinel_fqdns_raw <<< "${SENTINEL_POD_FQDN_LIST}"
  sentinel_fqdns=()
  for s in "${sentinel_fqdns_raw[@]}"; do
    [ -n "${s}" ] && sentinel_fqdns+=("${s}")
  done
  configured_count=${#sentinel_fqdns[@]}
  if [ "${configured_count}" -ge 1 ]; then
    min_valid=$((configured_count / 2 + 1))
    quorum_keys=()
    sentinel_query_success_count=0
    sentinel_master_config_count=0
    for s in "${sentinel_fqdns[@]}"; do
      sentinel_out=$(valkey-cli --no-auth-warning -h "${s}" -p "${sentinel_port}" ${sentinel_auth_args} ${sentinel_tls_args} sentinel masters 2>/dev/null) || continue
      sentinel_query_success_count=$((sentinel_query_success_count + 1))
      sentinel_has_master_config=0
      ce_marker=""
      runid_marker=""
      flags_marker=""
      epoch=""
      runid=""
      flags=""
      while IFS= read -r sline; do
        sline="${sline%$'\r'}"
        if [ -n "${ce_marker}" ]; then
          epoch="${sline}"
          ce_marker=""
        elif [ -n "${runid_marker}" ]; then
          runid="${sline}"
          runid_marker=""
        elif [ -n "${flags_marker}" ]; then
          flags="${sline}"
          flags_marker=""
        else
          case "${sline}" in
            "name")         sentinel_has_master_config=1 ;;
            "config-epoch") sentinel_has_master_config=1; ce_marker="1" ;;
            "runid")        sentinel_has_master_config=1; runid_marker="1" ;;
            "flags")        sentinel_has_master_config=1; flags_marker="1" ;;
          esac
        fi
        [ -n "${epoch}" ] && [ -n "${runid}" ] && [ -n "${flags}" ] && break
      done <<<"${sentinel_out}"
      if [ "${sentinel_has_master_config}" -eq 1 ] || [ -n "${epoch}" ] || [ -n "${runid}" ] || [ -n "${flags}" ]; then
        sentinel_master_config_count=$((sentinel_master_config_count + 1))
      fi
      __drop_reason=""
      # Validate: epoch must be uint64.
      case "${epoch}" in
        ''|*[!0-9]*) __drop_reason="epoch_not_uint64" ;;
      esac
      if [ -z "${__drop_reason}" ]; then
        # Validate: runid must be a non-empty hex token (no fixed length).
        case "${runid}" in
          ''|*[!0-9a-fA-F]*) __drop_reason="runid_empty_or_non_hex" ;;
        esac
      fi
      if [ -z "${__drop_reason}" ]; then
        # Validate: master flags must not include transient or failure
        # markers. A sentinel that flags the master as failover_in_progress
        # / force_failover / s_down / o_down is mid-transition; including
        # its view in the quorum would mistake the transient state for
        # consensus.
        case ",${flags}," in
          *,failover_in_progress,*) __drop_reason="flags_failover_in_progress" ;;
          *,force_failover,*)       __drop_reason="flags_force_failover" ;;
          *,s_down,*)               __drop_reason="flags_s_down" ;;
          *,o_down,*)               __drop_reason="flags_o_down" ;;
        esac
      fi
      __debug_append "{\"fqdn\":\"${s}\",\"epoch\":\"${epoch}\",\"runid\":\"${runid}\",\"flags\":\"${flags}\",\"drop\":\"${__drop_reason}\"}"
      if [ -n "${__drop_reason}" ]; then
        continue
      fi
      quorum_keys+=("${epoch}:${runid}")
    done
    valid_count=${#quorum_keys[@]}
    if [ "${valid_count}" -lt "${min_valid}" ]; then
      if [ "${sentinel_query_success_count}" -gt 0 ] && [ "${sentinel_master_config_count}" -eq 0 ]; then
        __quorum_decision_reason="bootstrap_no_sentinel_master"
      else
        __quorum_decision_reason="insufficient_valid"
      fi
    else
      first_key="${quorum_keys[0]}"
      all_agree=1
      for k in "${quorum_keys[@]}"; do
        if [ "${k}" != "${first_key}" ]; then
          all_agree=0
          break
        fi
      done
      if [ "${all_agree}" = 1 ]; then
        engine_version="${first_key%%:*}"
        sentinel_master_runid="${first_key#*:}"
        __quorum_decision_reason="versioned"
      else
        __quorum_decision_reason="split_view"
      fi
    fi
  else
    __quorum_decision_reason="no_sentinel_configured"
  fi
else
  __quorum_decision_reason="no_sentinel_env"
fi
set_xtrace_when_ut_mode_false

# Resolve the versioned role token from the Sentinel quorum.
# `engine_version` and `sentinel_master_runid` are set only when a
# strict-majority quorum agrees on a single `(epoch, runid)`. The role
# is decided purely by comparing the quorum's `runid` to this Pod's
# `INFO server` `run_id`: match → `primary`, mismatch → `secondary`.
# Local `INFO replication role:master` is intentionally NOT used as an
# input here — it lagged on the deposed primary and produced the V1
# round-3 race the quorum gate is supposed to close.
authoritative_role=""
if [ -n "${engine_version}" ] && [ -n "${sentinel_master_runid}" ]; then
  if [ -n "${local_run_id}" ] && [ "${local_run_id}" = "${sentinel_master_runid}" ]; then
    authoritative_role="primary"
  else
    authoritative_role="secondary"
  fi
fi
__quorum_emit_role="${authoritative_role}"

# Write the diagnostic record (if VALKEY_CHECK_ROLE_DEBUG=1) to a Pod-
# local file. Stdout is left untouched — production roleProbe contract
# is preserved. Per Bob2 + Edward 2026-05-24 review:
#   - debug never writes to stdout (would corrupt the role token)
#   - per-call line includes wall timestamp, pod identity, local
#     run_id, configured/min_valid/valid counts, per-sentinel raw
#     (epoch, runid, flags) plus filter drop reason, final decision
#     (versioned | legacy reason), emitted role + epoch.
# Output is a JSON-shaped one-liner so it stays grep-friendly while
# preserving the per-sentinel structure for later analysis.
if [ -n "${__check_role_debug_log}" ]; then
  __debug_ts=$(date -u +%Y-%m-%dT%H:%M:%S.%N%z 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)
  __debug_pod="${CURRENT_POD_NAME:-${HOSTNAME:-unknown}}"
  __debug_versioned_payload=""
  if [ -n "${engine_version}" ] && [ -n "${sentinel_master_runid}" ]; then
    __debug_versioned_payload=",\"emit_epoch\":\"${engine_version}\",\"emit_runid\":\"${sentinel_master_runid}\",\"emit_role\":\"${__quorum_emit_role}\""
  fi
  # One probe call = one line on disk (JSONL). Per Edward msg=be0a283c:
  # multi-line records would mis-align with controller event payloads
  # during analysis.
  {
    printf '{"ts":"%s","pod":"%s","local_run_id":"%s","configured_count":%s,"min_valid":%s,"valid_count":%s,"decision":"%s"%s,"sentinels":[%s]}\n' \
      "${__debug_ts}" \
      "${__debug_pod}" \
      "${local_run_id}" \
      "${configured_count:-0}" \
      "${min_valid:-0}" \
      "${valid_count:-0}" \
      "${__quorum_decision_reason}" \
      "${__debug_versioned_payload}" \
      "${__debug_records}"
  } >> "${__check_role_debug_log}" 2>/dev/null || true
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
  # Legacy single-token fallback. The mode of fallback matters: when
  # Sentinel is *not configured at all* the local INFO is the only
  # authority and `role:master` legitimately means `primary`. The same is
  # true during bootstrap when configured Sentinels answer but none has a
  # master record yet: postProvision cannot run until one pod is labelled
  # primary. But when Sentinel *is* configured and the quorum is merely
  # transiently invalid (split-view, insufficient_valid, flags transient,
  # missing auth), a sibling pod may already hold an engine-versioned
  # `primary` annotation on the controller. Emitting plain legacy
  # `primary` from this Pod's `role:master` in that window lets the
  # controller's cross-mode `removeExclusiveRoleLabels` strip the
  # sibling's engine-versioned label, after which the controller's strict
  # `engine:>` gate refuses to repair the missing label even when this
  # Pod resumes emitting versioned output (the same-version events are
  # rejected as staleRoleEventVersion).
  #
  # Safe degrade: when Sentinel is configured but quorum is transiently
  # invalid, local `role:master` fails this probe sample instead of
  # emitting any role. KB controller treats a non-zero roleProbe event as
  # "skip this sample", so an existing trusted primary label is preserved
  # while Sentinel recovers. Local `role:slave` still emits `secondary`:
  # a demotion is safe and must not leave a stale primary label behind.
  # When Sentinel is not configured / not envvar-provided
  # (`no_sentinel_env` / `no_sentinel_configured`), or configured
  # Sentinels have not registered their first master yet
  # (`bootstrap_no_sentinel_master`), keep the original local-INFO mapping
  # because that is the only available authority for the startup path.
  case "${__quorum_decision_reason}" in
    no_sentinel_env|no_sentinel_configured|bootstrap_no_sentinel_master)
      case "${role_line}" in
        "role:master") printf %s "primary"   ;;
        "role:slave")  printf %s "secondary" ;;
        *)
          echo "unknown role: '${role_line}'" >&2
          exit 1
          ;;
      esac
      ;;
    *)
      # insufficient_valid / split_view / future quorum-invalid reasons.
      case "${role_line}" in
        "role:master")
          # Do not emit a role token here; stdout must stay empty so the
          # controller cannot accept a stale local master self-report as
          # primary.
          echo "sentinel quorum invalid (${__quorum_decision_reason}); skipping master role update" >&2
          exit 1
          ;;
        "role:slave") printf %s "secondary" ;;
        *)
          echo "unknown role: '${role_line}'" >&2
          exit 1
          ;;
      esac
      ;;
  esac
fi
