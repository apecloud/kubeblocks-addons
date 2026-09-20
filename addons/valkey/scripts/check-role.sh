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
#   Role resolution order (Sentinel first, local fallback):
#     1. Sentinel component present → ask a Sentinel for the master record it
#        keeps under this component's name (`SENTINEL master <name>`, name =
#        VALKEY_COMPONENT_NAME — the same name the register-to-sentinel /
#        member-join scripts pass to `SENTINEL MONITOR`) and trust its
#        `runid`: this Pod is `primary` only when its local `INFO server`
#        `run_id` equals that `runid`, otherwise `secondary`. The Sentinel
#        `config-epoch` is appended as the second token.
#     2. No Sentinel component, or nothing usable could be taken from
#        Sentinel (not configured / unreachable / NOAUTH / no master record
#        under that name / non-uint64 epoch / non-hex runid / transient
#        master flags) → fall back to this Pod's own `INFO replication`:
#        `role:master` → `primary`, `role:slave` → `secondary`. No second
#        token is emitted on this path, so the controller falls back to its
#        EventTime gate.
#     3. Anything else (unknown local role) → non-zero exit so KubeBlocks
#        skips this sample instead of labelling the Pod with a bogus role.
#
#   Why the runid check matters: after a Sentinel-driven failover the deposed
#   primary keeps reporting `role:master` locally for a brief window.
#   Comparing `run_id` against the Sentinel master `runid` keeps that Pod at
#   `secondary` while both Pods would otherwise emit the same version token,
#   so two Pods cannot both claim `primary <same-epoch>`.
#
#   Query targets: the Sentinel headless service
#   (SENTINEL_HEADLESS_SVC_HOST — a serviceVarRef to the sentinel component's
#   `headless` service) is asked first, then the individual Sentinel pods
#   (SENTINEL_POD_FQDN_LIST) as a fallback, but at most
#   SENTINEL_MAX_ATTEMPTS hosts in total so a slow or black-holed Sentinel set
#   cannot eat the whole roleProbe budget (timeoutSeconds 3). Every attempt is
#   wrapped in `timeout 1`.
#
#   Using valkey-cli (not redis-cli) because Valkey ships its own CLI.
#   The -h 127.0.0.1 ensures we hit this pod's own server.
#
#   KB_SERVICE_PORT / KB_HOST_IP / KB_POD_FQDN are injected by the roleProbe
#   env[] block in the ComponentDefinition (not from vars[]).
#
# This script is pure read-and-emit — it performs NO repair itself:
#   - It runs on the kbagent-driven roleProbe path (periodSeconds 5,
#     timeoutSeconds 3), where extra work risks exceeding the probe budget,
#     and forking helpers from that path leaks zombies in the kbagent
#     container (kbagent's PID 1 is a Go binary that does not reap orphans).
#   - There is intentionally no in-container repair loop anymore: the
#     periodic cascade-topology / full-sync-stall / dual-master daemon
#     (valkey-self-heal.sh) was removed on purpose.  Cascade repair is left
#     to Sentinel (which fixes the instances it discovered) and topology
#     damage that Sentinel cannot see is repaired out-of-band — restarting
#     the pod re-derives the primary from the Sentinel quorum via
#     build_replicaof_config() in valkey-start.sh.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
# Name under which this component is monitored by Sentinel. It is the value
# the register / member-join scripts pass to `SENTINEL MONITOR`, so it is the
# only name that can be looked up on the Sentinel side.
sentinel_master_name="${VALKEY_COMPONENT_NAME:-}"
# Upper bound on the Sentinel hosts contacted per probe call. Each attempt is
# wrapped in `timeout 1` while the probe itself has timeoutSeconds 3, so the
# ceiling keeps a broken Sentinel set from starving the probe.
sentinel_max_attempts="${SENTINEL_MAX_ATTEMPTS:-3}"

build_cli_cmd() {
  cli_cmd=(valkey-cli --no-auth-warning -h 127.0.0.1 -p "${port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

# parse_role_line <info replication output> — print the first `role:` line
# (empty while the server has not answered yet, e.g. during startup).
parse_role_line() {
  local line
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "${line}" in
      role:*) printf %s "${line}"; return 0 ;;
    esac
  done <<<"${1}"
}

# parse_run_id <info server output> — print the server `run_id`.
parse_run_id() {
  local line
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "${line}" in
      run_id:*) printf %s "${line#run_id:}"; return 0 ;;
    esac
  done <<<"${1}"
}

# collect_sentinel_targets — print the hosts to ask, one per line: the
# Sentinel headless service first, then the individual Sentinel pods. Empty
# entries (trailing commas, unset vars) and duplicates are dropped. Pure bash
# (no child process), and it prints instead of exporting so the unit tests can
# assert the order directly.
collect_sentinel_targets() {
  local raw part existing seen_it
  local printed=()
  for raw in "${SENTINEL_HEADLESS_SVC_HOST:-}" "${SENTINEL_POD_FQDN_LIST:-}"; do
    [ -n "${raw}" ] || continue
    local -a parts=()
    IFS=',' read -ra parts <<<"${raw}"
    for part in "${parts[@]}"; do
      [ -n "${part}" ] || continue
      seen_it=0
      for existing in "${printed[@]:-}"; do
        if [ "${existing}" = "${part}" ]; then
          seen_it=1
          break
        fi
      done
      [ "${seen_it}" -eq 0 ] || continue
      printed+=("${part}")
      printf '%s\n' "${part}"
    done
  done
}

# sentinel_query_master_record <host> — ask one Sentinel for the record of
# `sentinel_master_name` and export the fields we trust:
#   SENTINEL_RECORD_EPOCH / SENTINEL_RECORD_RUNID / SENTINEL_RECORD_FLAGS
# Returns 0 only when the answer is usable, i.e. the record belongs to our
# master name, `config-epoch` is a clean uint64, `runid` is a non-empty hex
# token, and the master flags carry no transient/failure marker. The rejection
# reason is left in SENTINEL_RECORD_DROP for the callers and the unit tests.
#
# One `valkey-cli ... sentinel master <name>` child per attempt, parsed with
# bash builtins only: pipelines would spawn extra children that outlive a
# kbagent SIGKILL on probe timeout (zombie accumulation under PID 1).
sentinel_query_master_record() {
  local host="$1"
  SENTINEL_RECORD_DROP=""
  local -a sentinel_auth_args=()
  if [ -n "${SENTINEL_PASSWORD:-}" ]; then
    sentinel_auth_args=(-a "${SENTINEL_PASSWORD}")
  fi

  local out
  # shellcheck disable=SC2086
  out=$(timeout 1 valkey-cli --no-auth-warning -h "${host}" -p "${sentinel_port}" \
          "${sentinel_auth_args[@]}" ${VALKEY_CLI_TLS_ARGS:-} \
          sentinel master "${sentinel_master_name}" 2>/dev/null) || true
  if [ -z "${out}" ]; then
    SENTINEL_RECORD_DROP="no_answer"
    return 1
  fi

  local marker="" line name="" epoch="" runid="" flags=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    if [ -n "${marker}" ]; then
      case "${marker}" in
        name)         name="${line}"  ;;
        runid)        runid="${line}" ;;
        config-epoch) epoch="${line}" ;;
        flags)        flags="${line}" ;;
      esac
      marker=""
      [ -n "${name}" ] && [ -n "${runid}" ] && [ -n "${epoch}" ] && [ -n "${flags}" ] && break
      continue
    fi
    case "${line}" in
      name|runid|config-epoch|flags) marker="${line}" ;;
    esac
  done <<<"${out}"

  # A record for another master name (or no name field at all) is not ours.
  if [ "${name}" != "${sentinel_master_name}" ]; then
    SENTINEL_RECORD_DROP="wrong_master_name"
    return 1
  fi
  case "${epoch}" in
    ''|*[!0-9]*)
      SENTINEL_RECORD_DROP="epoch_not_uint64"
      return 1
      ;;
  esac
  case "${runid}" in
    ''|*[!0-9a-fA-F]*)
      SENTINEL_RECORD_DROP="runid_empty_or_non_hex"
      return 1
      ;;
  esac
  case ",${flags}," in
    *,failover_in_progress,*|*,force_failover,*|*,s_down,*|*,o_down,*)
      SENTINEL_RECORD_DROP="flags_transient"
      return 1
      ;;
  esac

  SENTINEL_RECORD_EPOCH="${epoch}"
  SENTINEL_RECORD_RUNID="${runid}"
  SENTINEL_RECORD_FLAGS="${flags}"
  return 0
}

# decide_role <local role line> <local run_id> <sentinel master runid> <epoch>
# Prints the role token (plus the engine version when one is available):
#   - Sentinel record usable → `primary`/`secondary` decided by the runid
#     comparison (the local INFO role is deliberately NOT the authority here),
#     followed by the Sentinel config-epoch as the version token.
#   - No usable Sentinel record → local INFO mapping, single token.
#   - Unknown local role → exit 1 so KubeBlocks skips the sample.
decide_role() {
  local role_line="$1" local_run_id="$2" master_runid="$3" engine_version="$4"
  if [ -n "${master_runid}" ] && [ -n "${engine_version}" ]; then
    if [ -n "${local_run_id}" ] && [ "${local_run_id}" = "${master_runid}" ]; then
      printf '%s' "primary"
    else
      printf '%s' "secondary"
    fi
    return 0
  fi
  case "${role_line}" in
    "role:master") printf %s "primary" ;;
    "role:slave")  printf %s "secondary" ;;
    *)
      echo "unknown role: '${role_line}'" >&2
      exit 1
      ;;
  esac
}

__check_role_main() {
  build_cli_cmd

  unset_xtrace_when_ut_mode_false
  # Capture INFO replication and INFO server with one command substitution
  # each (one valkey-cli child per call) and parse them with bash builtins.
  # Pipelines like `... | grep | tr` would spawn one child per stage; when
  # kbagent SIGKILLs this script for exceeding probe timeoutSeconds those
  # children are reparented to kbagent's PID 1 (a Go binary that does not
  # reap unrelated children) and accumulate as zombies.
  repl_info=$("${cli_cmd[@]}" info replication 2>/dev/null) || repl_info=""
  server_info=$("${cli_cmd[@]}" info server 2>/dev/null) || server_info=""
  # The parsers are pure bash and short-lived, so these substitutions spawn no
  # blocking child.
  role_line=$(parse_role_line "${repl_info}")
  local_run_id=$(parse_run_id "${server_info}")

  # ── 1. Sentinel first: the master record kept under our component name ──
  engine_version=""
  sentinel_master_runid=""
  sentinel_decision=""
  attempts=0
  if [ -z "${sentinel_master_name}" ]; then
    sentinel_decision="local_fallback:no_master_name"
  elif [ -z "${SENTINEL_HEADLESS_SVC_HOST:-}" ] && [ -z "${SENTINEL_POD_FQDN_LIST:-}" ]; then
    sentinel_decision="local_fallback:no_sentinel_component"
  else
    sentinel_targets_raw=$(collect_sentinel_targets)
    while IFS= read -r target; do
      [ -n "${target}" ] || continue
      [ "${attempts}" -lt "${sentinel_max_attempts}" ] || break
      attempts=$((attempts + 1))
      if sentinel_query_master_record "${target}"; then
        engine_version="${SENTINEL_RECORD_EPOCH}"
        sentinel_master_runid="${SENTINEL_RECORD_RUNID}"
        sentinel_decision="sentinel_authoritative"
        break
      fi
    done <<<"${sentinel_targets_raw}"
    if [ -z "${sentinel_decision}" ]; then
      sentinel_decision="local_fallback:no_usable_sentinel_record"
    fi
  fi
  set_xtrace_when_ut_mode_false

  # ── 2. Emit the token ─────────────────────────────────────────────────
  # roleProbe parses stdout with `strings.Fields`, so both the single-token
  # and the two-token form are accepted; only the first token becomes the Pod
  # role label.
  decide_role "${role_line}" "${local_run_id}" "${sentinel_master_runid}" "${engine_version}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library
__check_role_main
