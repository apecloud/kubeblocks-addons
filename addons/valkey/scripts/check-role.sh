#!/bin/bash
# check-role.sh — roleProbe script for KubeBlocks.
#
# Learning note:
#   KubeBlocks calls this script every periodSeconds seconds on EACH pod.
#
#   Output contract: the controller shares the WHOLE stdout as the role and
#   looks that string up in the ComponentDefinition's roles[] map.  A match
#   sets the pod's `kubeblocks.io/role` label; **anything that does not match a
#   role name — an extra whitespace-separated token such as a version, a
#   sentence, or an empty string — makes the controller DELETE the label**.
#   So this script prints exactly one of: `primary`, `secondary`, or (only when
#   no Sentinel answered at all, see rule 2) nothing.
#
#   Role resolution order — a majority vote over the whole Sentinel fleet:
#     1. Ask EVERY Sentinel for the master address of this component
#        (`SENTINEL GET-MASTER-ADDR-BY-NAME <VALKEY_COMPONENT_NAME>`; the reply
#        is two lines: host and port).  The address reported by the MOST
#        Sentinels is the cluster master.  This Pod is `primary` iff the winning
#        address is its OWN advertised address, otherwise `secondary`.
#        Only one address can win a vote, so at most one Pod can call itself
#        primary — no ping-pong over the exclusive `primary` label.
#     2. Every Sentinel query FAILED (connection refused / reset / timed out, or
#        credentials refused) → print NOTHING.  Nobody could tell us who the
#        master is, so this Pod has no confirmed role.  KubeBlocks 1.0.x turns
#        that into "no role label on this Pod" (see the output contract above).
#     3. At least one Sentinel ANSWERED but none knows a master (an unknown
#        master name yields an empty reply) → nothing has been registered as
#        master yet (cluster bootstrap / registration pending): fall back to
#        this Pod's own `INFO replication` — `role:master` → `primary`,
#        `role:slave` → `secondary`.  Any other local role exits non-zero, so
#        the controller skips the sample instead of writing a bogus role.
#
#   Why the vote is needed (the TLS rolling window): when TLS is enabled on
#   both the Sentinel and the data component, KubeBlocks rolls the Sentinel
#   fleet first and Sentinel comes up TLS-only (`port 0` + `tls-port`).  Data
#   pods that have not been rolled yet still speak plaintext, so they cannot
#   reach Sentinel at all — and the pod that has not been rolled yet is
#   typically the one that was the primary before the change.  If such a Pod
#   fell back to its own `INFO replication` it would keep reporting `primary`
#   while the Sentinel-confirmed master reported `primary` too, and the
#   controller would ping-pong the exclusive `primary` label between them
#   ("remove exclusive role label" + conflicting pod updates) while the rolling
#   update never reached the stale pod.  Voting on the Sentinel-reported
#   address, and refusing to guess when nobody answered, ends that.
#
#   Query targets: the Sentinel headless service
#   (SENTINEL_HEADLESS_SVC_HOST — a serviceVarRef to the sentinel component's
#   `headless` service) is asked first, then the individual Sentinel pods
#   (SENTINEL_POD_FQDN_LIST).  All of them are asked (the vote wants every
#   answer); SENTINEL_MAX_ATTEMPTS can cap the number of hosts when a cluster
#   has a very large Sentinel fleet.  Every attempt is wrapped in `timeout 1`
#   so a black-holed Sentinel cannot eat the whole roleProbe budget
#   (timeoutSeconds 3).
#
#   Using valkey-cli (not redis-cli) because Valkey ships its own CLI.
#   The -h 127.0.0.1 ensures we hit this pod's own server.
#
#   KB_SERVICE_PORT / KB_HOST_IP / KB_POD_FQDN / CURRENT_POD_NAME /
#   KB_CLUSTER_COMP_NAME are injected by the roleProbe env[] block in the
#   ComponentDefinition (not from vars[]).  The pod's own advertised address is
#   read from the runtime conf written by valkey-start.sh
#   (`replica-announce-ip` / `replica-announce-port`) — that is the only way to
#   tell which Pod a NodePort / LoadBalancer address refers to.
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
#     get_primary_addr_from_sentinels() in valkey-start.sh.

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
# Number of Sentinel hosts contacted per probe. 0 (the default) means "ask all
# of them": the majority vote wants every answer, and each attempt is bounded
# by `timeout 1` anyway.
sentinel_max_attempts="${SENTINEL_MAX_ATTEMPTS:-0}"
# Runtime configuration written by valkey-start.sh; carries this pod's own
# `replica-announce-ip` / `replica-announce-port`.
runtime_conf="${VALKEY_CONF_RUNTIME:-/etc/valkey/valkey.conf}"

# This Pod's own advertised address, filled by read_own_announce_addr().
announce_host=""
announce_port=""

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

# sentinel_query_master_addr <host> — ask one Sentinel which address is the
# master of `sentinel_master_name` and export it:
#   SENTINEL_ADDR_HOST / SENTINEL_ADDR_PORT
# Returns 1 with the reason in SENTINEL_ADDR_DROP when there is no address:
#   unreachable  — the connection itself failed (refused, reset, TLS mismatch,
#                  timed out): valkey-cli exits non-zero and stdout is empty.
#   auth_refused — the Sentinel answered that our credentials are not accepted.
#   no_master    — the Sentinel ANSWERED but keeps no record under our name.
#                  Verified against a live Sentinel: an unknown master name
#                  yields an empty reply and exit code 0, which is what tells
#                  this apart from `unreachable`.
#
# One `valkey-cli ... get-master-addr-by-name` child per attempt, parsed with
# bash builtins only: pipelines would spawn extra children that outlive a
# kbagent SIGKILL on probe timeout (zombie accumulation under PID 1).
sentinel_query_master_addr() {
  local host="$1"
  SENTINEL_ADDR_DROP=""
  SENTINEL_ADDR_HOST=""
  SENTINEL_ADDR_PORT=""
  local -a sentinel_auth_args=()
  if [ -n "${SENTINEL_PASSWORD:-}" ]; then
    sentinel_auth_args=(-a "${SENTINEL_PASSWORD}")
  fi

  local out rc=0
  # shellcheck disable=SC2086
  out=$(timeout 1 valkey-cli --no-auth-warning -h "${host}" -p "${sentinel_port}" \
          "${sentinel_auth_args[@]}" ${VALKEY_CLI_TLS_ARGS:-} \
          sentinel get-master-addr-by-name "${sentinel_master_name}" 2>/dev/null) || rc=$?
  if [ "${rc}" -ne 0 ]; then
    SENTINEL_ADDR_DROP="unreachable"
    return 1
  fi

  # valkey-cli exits 0 on a protocol-level error reply, so the reply text is the
  # only way to recognise refused credentials.
  case "${out}" in
    *NOAUTH*|*WRONGPASS*|*"invalid password"*|*"without any password configured"*)
      SENTINEL_ADDR_DROP="auth_refused"
      return 1
      ;;
  esac

  # The reply is two lines: <host> and <port>.
  local line lineno=0
  while IFS= read -r line; do
    line="${line%$'\r'}"
    lineno=$((lineno + 1))
    case "${lineno}" in
      1) SENTINEL_ADDR_HOST="${line}" ;;
      2) SENTINEL_ADDR_PORT="${line}" ;;
    esac
  done <<<"${out}"

  case "${SENTINEL_ADDR_HOST}" in
    ""|"(nil)")
      # Answered, but nothing is registered under our master name yet.
      SENTINEL_ADDR_DROP="no_master"
      return 1
      ;;
  esac
  [ -n "${SENTINEL_ADDR_PORT}" ] || SENTINEL_ADDR_PORT="${port}"
  return 0
}

# vote_master_addr <newline separated "host:port" answers> — print the address
# the most Sentinels reported, or nothing when there is no answer at all.
# Ties are broken lexicographically so the outcome is deterministic: exactly one
# address can win, so at most one Pod can consider itself the primary.
vote_master_addr() {
  local answers="$1" line key
  local -A counts=()
  local best_key="" best_count=0

  while IFS= read -r line; do
    [ -n "${line}" ] || continue
    key="${line}"
    counts["${key}"]=$(( ${counts["${key}"]:-0} + 1 ))
  done <<<"${answers}"

  for key in "${!counts[@]}"; do
    if [ "${counts[${key}]}" -gt "${best_count}" ] ||
      { [ "${counts[${key}]}" -eq "${best_count}" ] && [ -n "${best_key}" ] && [ "${key}" \< "${best_key}" ]; }; then
      best_key="${key}"
      best_count="${counts[${key}]}"
    fi
  done

  if [ -n "${best_key}" ]; then
    printf '%s' "${best_key}"
  fi
  return 0
}

# read_own_announce_addr — fill announce_host / announce_port from the runtime
# conf written by valkey-start.sh (build_announce_addr). NodePort and
# LoadBalancer deployments announce `<node-ip>:<this pod's NodePort>` (or
# `<LB host>:<port>`), and that pair is the only way to tell which Pod a
# Sentinel-reported address belongs to. An unreadable conf simply disables that
# rule: pod-FQDN announces are matched by name instead.
read_own_announce_addr() {
  announce_host=""
  announce_port=""
  [ -r "${runtime_conf}" ] || return 0

  local line value
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "${line}" in
      "replica-announce-ip "*)
        value="${line#replica-announce-ip }"
        value="${value%\"}"
        announce_host="${value#\"}"
        ;;
      "replica-announce-port "*)
        value="${line#replica-announce-port }"
        value="${value%\"}"
        announce_port="${value#\"}"
        ;;
    esac
  done <"${runtime_conf}"
  return 0
}

# is_own_master_addr <host> <port> — is this address the one of the pod this
# script runs on?  Two rules, the same ones valkey-start.sh uses:
#   1. pod-FQDN announce: the address is this pod's FQDN (KB_POD_FQDN) or a name
#      derived from `<pod-name>.<component-name>`, with or without the search
#      domain.
#   2. address announce (NodePort / LoadBalancer): the reported pair equals this
#      pod's own replica-announce pair.
is_own_master_addr() {
  local master_host="$1" master_port="$2"

  if [ -n "${KB_POD_FQDN:-}" ] && [ "${master_host}" = "${KB_POD_FQDN}" ]; then
    return 0
  fi
  if [ -n "${CURRENT_POD_NAME:-}" ]; then
    case "${master_host}" in
      "${CURRENT_POD_NAME}".*) return 0 ;;
    esac
  fi
  if [ -n "${announce_host}" ] && [ -n "${announce_port}" ] &&
    [ "${master_host}" = "${announce_host}" ] && [ "${master_port}" = "${announce_port}" ]; then
    return 0
  fi
  return 1
}

# decide_role <local role line> <mode> [detail] — print exactly one role token
# (or nothing, or exit non-zero to make KubeBlocks skip the sample):
#   voted          → a Sentinel-majority address is in voted_host/voted_port:
#                    `primary` when it is this pod's own address, else
#                    `secondary`.
#   local_authority → no Sentinel knows a master (bootstrap), so this pod's own
#                    INFO replication is the only authority: `role:master` →
#                    `primary`, `role:slave` → `secondary`.
#   no_authority   → every Sentinel query failed: print NOTHING.  `detail`
#                    carries the failure reason for the stderr diagnostic.
decide_role() {
  local role_line="$1" mode="$2" detail="${3:-unknown}"

  case "${mode}" in
    voted)
      if is_own_master_addr "${voted_host}" "${voted_port}"; then
        printf '%s' "primary"
      else
        printf '%s' "secondary"
      fi
      ;;
    no_authority)
      printf '%s' "secondary"
      ;;
    *)
      case "${role_line}" in
        "role:master") printf %s "primary" ;;
        "role:slave")  printf %s "secondary" ;;
        *)
          echo "unknown role: '${role_line}'" >&2
          exit 1
          ;;
      esac
      ;;
  esac
  return 0
}

__check_role_main() {
  build_cli_cmd

  unset_xtrace_when_ut_mode_false
  # Capture INFO replication with one command substitution (one valkey-cli child)
  # and parse it with bash builtins. Pipelines like `... | grep | tr` would spawn
  # one child per stage; when kbagent SIGKILLs this script for exceeding probe
  # timeoutSeconds those children are reparented to kbagent's PID 1 (a Go binary
  # that does not reap unrelated children) and accumulate as zombies.
  repl_info=$("${cli_cmd[@]}" info replication 2>/dev/null) || repl_info=""
  # The parser is pure bash and short-lived, so this substitution spawns no
  # blocking child.
  role_line=$(parse_role_line "${repl_info}")
  # The pod's own announced address comes from the runtime conf (pure bash read).
  read_own_announce_addr

  # ── 1. Majority vote over the whole Sentinel fleet ──────────────────────
  voted_host=""
  voted_port=""
  sentinel_mode="local_authority"
  sentinel_detail="no_sentinel_component"
  if [ -z "${sentinel_master_name}" ]; then
    # Without the component name there is no master name to look up, so the
    # Sentinel fleet cannot be asked at all; keep the historical local
    # behaviour.
    sentinel_detail="no_master_name"
  elif [ -z "${SENTINEL_HEADLESS_SVC_HOST:-}" ] && [ -z "${SENTINEL_POD_FQDN_LIST:-}" ]; then
    sentinel_detail="no_sentinel_component"
  else
    sentinel_targets_raw=$(collect_sentinel_targets)
    sentinel_answers=""
    # `answered` counts every Sentinel that REPLYED (with an address, or with
    # "no master under that name"); `no_master` replies are successes without an
    # address, and only "did not answer at all" makes this pod role-less.
    sentinel_answered=0
    attempts=0
    while IFS= read -r target; do
      [ -n "${target}" ] || continue
      if [ "${sentinel_max_attempts}" -gt 0 ] && [ "${attempts}" -ge "${sentinel_max_attempts}" ]; then
        break
      fi
      attempts=$((attempts + 1))
      if sentinel_query_master_addr "${target}"; then
        sentinel_answered=$((sentinel_answered + 1))
        sentinel_answers+="${SENTINEL_ADDR_HOST}:${SENTINEL_ADDR_PORT}"$'\n'
      else
        sentinel_detail="${SENTINEL_ADDR_DROP}"
        if [ "${SENTINEL_ADDR_DROP}" = "no_master" ]; then
          sentinel_answered=$((sentinel_answered + 1))
        fi
      fi
    done <<<"${sentinel_targets_raw}"

    if [ "${sentinel_answered}" -eq 0 ]; then
      # Nobody answered: no role claim at all (see rule 2 in the header).
      sentinel_mode="no_authority"
    else
      voted_key=$(vote_master_addr "${sentinel_answers}")
      if [ -n "${voted_key}" ]; then
        voted_host="${voted_key%:*}"
        voted_port="${voted_key##*:}"
        sentinel_mode="voted"
      fi
      # else: answered, but no master registered yet → local_authority.
    fi
  fi
  set_xtrace_when_ut_mode_false

  # ── 2. Emit the token ──────────────────────────────────────────────────
  decide_role "${role_line}" "${sentinel_mode}" "${sentinel_detail}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library
__check_role_main
