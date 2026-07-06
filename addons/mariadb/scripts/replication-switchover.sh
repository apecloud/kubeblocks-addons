#!/bin/sh
# Switchover: ask syncer to coordinate ownership via DCS, then wait until
# database truth reflects the new primary and the old primary has followed it.
#
# Env vars set by KubeBlocks:
#   KB_SWITCHOVER_ROLE           - "primary" (only act when we are the primary)
#   KB_SWITCHOVER_CURRENT_NAME   - current primary pod name
#   KB_SWITCHOVER_CANDIDATE_NAME - target replica pod name (may be empty)

DATA_DIR="${MARIADB_DATADIR:-/var/lib/mysql}"
CLUSTER_DOMAIN="${CLUSTER_DOMAIN:-cluster.local}"
SYNCERCTL_BIN="${SYNCERCTL_BIN:-/tools/syncerctl}"
SYNCERCTL_HOST="${SYNCERCTL_HOST:-127.0.0.1}"
SYNCERCTL_PORT="${SYNCERCTL_PORT:-3601}"
SWITCHOVER_POLL_SECONDS="${SWITCHOVER_POLL_SECONDS:-1}"
# alpha.59: kbagent enforces maxActionCallTimeout=60s
# (pkg/kbagent/service/action_utils.go). The switchover action is intentionally
# bounded to a small budget; post-DCS convergence (Primary Service endpoint,
# old-primary follow, secondary remote root fence, kb_health_check 1062 repair)
# is delegated to roleProbe + KB endpoint controller. The candidate write probe
# is still synchronous because it is part of the action's success contract:
# action returns 0 only after we have proven the candidate is actually writable.
#
# alpha.61: action now uses a single global deadline rather than per-stage
# fixed sleeps. This avoids the trap where the sum of per-stage sleep budgets
# exceeds the kbagent 60s ceiling under unusual timing. SWITCHOVER_ACTION_DEADLINE_SECONDS
# is the hard contract; per-stage maxima are clamped by the remaining global
# deadline at runtime.
#
# alpha.61 v2 (Jack 02:00 review): POSIX-portable wall clock + 5-stage
# enforcement. The original v1 used bash-only $SECONDS / $'\n' case patterns
# under #!/bin/sh shebang -- in dash $SECONDS is not auto-incrementing, so the
# deadline expression evaluated to 0 forever and the stage loops would only be
# bounded by the kbagent 60s ceiling, defeating the v1 fix. v2 uses
# now_epoch()/initialize_action_clock()/remaining_action_budget()/
# stage_budget_or_exit() helpers built on `date +%s`, `printf|awk`, and
# `command -v timeout`; failures of these primitives are fatal so we never
# silently run with a broken clock or unbounded external calls. Each stage
# (prepare/candidate_connect/dcs/fence/promote/ready) checks the remaining
# global budget at entry and emits action_deadline_exhausted_<stage> if
# exhausted.
SWITCHOVER_ACTION_DEADLINE_SECONDS="${SWITCHOVER_ACTION_DEADLINE_SECONDS:-55}"
SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS="${SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS:-10}"
SWITCHOVER_CANDIDATE_CONNECT_READY_WAIT_SECONDS="${SWITCHOVER_CANDIDATE_CONNECT_READY_WAIT_SECONDS:-12}"
SWITCHOVER_CANDIDATE_CONNECT_READY_POLL_SECONDS="${SWITCHOVER_CANDIDATE_CONNECT_READY_POLL_SECONDS:-1}"
SWITCHOVER_CANDIDATE_CONNECT_READY_CONNECT_TIMEOUT_SECONDS="${SWITCHOVER_CANDIDATE_CONNECT_READY_CONNECT_TIMEOUT_SECONDS:-1}"
SWITCHOVER_DCS_STAGE_BUDGET_SECONDS="${SWITCHOVER_DCS_STAGE_BUDGET_SECONDS:-15}"
SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS="${SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS:-15}"
CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS="${CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS:-30}"
# alpha.77 v2 (Helen TL): bumped from 10s -> 30s. alpha.77 v1 N=1 verify on
# n1y closed the pre-DCS REMOTE root fence race (stages 1-4 all PASS, no
# `bypass_priv_residual` in stderr) but failed at stage 5 because the new
# primary's chart watchdog SECONDARY -> PRIMARY role transition takes longer
# than 10s. Direct evidence: pod-1 watchdog log at 11:40:21-23 still running
# replica-read-only LOCK while DCS swap completed at 11:40:19; stage 5
# attempts 1-3 saw 1044/1290 (account still locked / read_only still ON)
# followed by 2002 (mariadbd briefly unreachable during stop+start_mariadbd
# rebind from 127.0.0.1 to 0.0.0.0 inside expose_sql_listener_for_primary_
# role). 30s gives the new primary watchdog one full role-transition cycle
# (~6-10s typical) + headroom. Env override still respected.
#
# alpha.127: stage 5 no longer performs a mutating remote root DDL/DML probe.
# r9 showed that repeating the probe can leave orphan GTIDs on a temporary
# candidate when role flaps: CREATE DATABASE + INSERT/DELETE in
# kb_root_write_probe were logged locally and later made CM4 fail-closed on
# GTID divergence. Keep the old env var as a compatibility default, but the
# runtime gate is now a non-mutating root primary-readiness check.
CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS="${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS:-30}"
CANDIDATE_REMOTE_ROOT_PRIMARY_READY_WAIT_SECONDS="${CANDIDATE_REMOTE_ROOT_PRIMARY_READY_WAIT_SECONDS:-${CANDIDATE_REMOTE_ROOT_WRITE_PROBE_WAIT_SECONDS}}"
MARIADB_CONNECT_TIMEOUT_SECONDS="${MARIADB_CONNECT_TIMEOUT_SECONDS:-5}"
SYNCERCTL_PER_CALL_TIMEOUT_SECONDS="${SYNCERCTL_PER_CALL_TIMEOUT_SECONDS:-5}"

# Mutable globals set by initialize_action_clock(); consumed by stage helpers.
action_started_epoch=""
SWITCHOVER_HAS_TIMEOUT=""
MYSQL_CLIENT_DIR="${MYSQL_CLIENT_DIR:-/tools/mysql-client}"
MARIADB_CLIENT_BIN="${MARIADB_CLIENT_BIN:-}"
MARIADB_INTERNAL_ROOT_USER="${MARIADB_INTERNAL_ROOT_USER:-kb_internal_root}"
SWITCHOVER_TRACE_FILE="${SWITCHOVER_TRACE_FILE:-}"
# Used only by the local old-primary fence probe. Candidate primary-readiness
# checks must stay non-mutating and must not use this table.
SWITCHOVER_REMOTE_ROOT_PROBE_TABLE="${SWITCHOVER_REMOTE_ROOT_PROBE_TABLE:-kubeblocks.kb_root_write_probe}"

# alpha.80 v1 (Helen TL): the alpha.76/.77/.78 `.switchover-fence-active`
# marker mechanism is now removed. alpha.79 v1 minimalist refactor (per
# westonnnn directive) eliminated the pre-DCS fence chain in
# `prepare_current_primary_for_switchover`, which was the SOURCE of the race
# the marker was designed to gate. With no fence chain, nothing writes the
# marker; with nothing writing it, the consumer-side checks in cmpd-semisync
# `reconcile_sql_listener_for_syncer_primary_once` / `set_remote_root_account
# _state` and roleprobe.sh `apply_remote_root_fence` always evaluate to
# "not fresh" and proceed normally. Keeping the helpers + consumer checks
# served no runtime purpose; alpha.80 v1 deletes them entirely.
#
# Scope: this is dead-code cleanup ONLY. No runtime behavior change. NOT a
# fix for same-cluster repeat RED, under-load data-divergence RED, or pod-
# kill 1032-rejoin RED — those each have their own first-blocker that
# remains open with separate evidence packets.

# alpha.62 v1 (Jack 04:08 review): contract drift between switchover-side
# pre-DCS fence and roleProbe-side secondary fence + verifier口径漂移. Single
# source of truth constants below are referenced by both fence/grant write
# sites AND verifier read sites — keep them in sync; ShellSpec strong-binds.
#
# Privileges that bypass `read_only=ON` and must NEVER appear on user-facing
# root after fence (alpha.61 secondary fence semantics).
SWITCHOVER_BYPASS_PRIVILEGES_PATTERN='READ_ONLY ADMIN|SUPER|BINLOG ADMIN|CONNECTION ADMIN|ALL PRIVILEGES'
# user-facing write privileges that must NEVER appear on user-facing root
# during secondary fence state. Verifier rejects any of these.
#
# alpha.63 v1 (Jack 05:22 RED closeout I-1): `GRANT OPTION` REMOVED from the
# pattern. It was a trailing-modifier token that over-matched the default
# `GRANT PROXY ... WITH GRANT OPTION` row that mariadb auto-creates and
# is unrelated to write privileges. The remaining priv tokens (INSERT/
# UPDATE/DELETE/CREATE/DROP/ALTER/CREATE USER) are unambiguous priv names
# that mean actual write access. Defense-in-depth: a line-anchored
# SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN whitelist is also applied
# BEFORE the priv scan, with grants_ignored_count + dump for audit.
SWITCHOVER_USER_FACING_WRITE_PATTERN='INSERT|UPDATE|DELETE|CREATE|DROP|ALTER|CREATE USER'

# alpha.63 v1 (Jack 05:24 instrumentation tightening 2): line-anchored
# whitelist of grant lines to be filtered out BEFORE bypass/write-residual
# scan. Today only the default GRANT PROXY row is whitelisted. The pattern
# is line-start + line-end anchored so that surprise variants like
# `GRANT INSERT ... WITH GRANT OPTION` are NOT silently filtered. The
# verifier counts and dumps ignored lines for audit.
SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN='^GRANT PROXY ON .* TO .* WITH GRANT OPTION$'

root_read_only_bypass_pattern_for_host() {
  case "${1}" in
    "127.0.0.1"|"localhost")
      printf '%s' 'READ_ONLY ADMIN|READ ONLY ADMIN|(^|[, ])SUPER([, ]|$)|ALL PRIVILEGES'
      ;;
    *)
      printf '%s' 'READ_ONLY ADMIN|READ ONLY ADMIN|BINLOG ADMIN|(^|[, ])SUPER([, ]|$)|ALL PRIVILEGES'
      ;;
  esac
}

root_read_only_bypass_label_for_host() {
  case "${1}" in
    "127.0.0.1"|"localhost")
      printf '%s' 'READ_ONLY ADMIN / SUPER / ALL PRIVILEGES'
      ;;
    *)
      printf '%s' 'READ_ONLY ADMIN / BINLOG ADMIN / SUPER / ALL PRIVILEGES'
      ;;
  esac
}

root_post_dcs_revoke_privilege_list_for_host() {
  case "${1}" in
    "127.0.0.1"|"localhost")
      printf '%s\n%s\n' "READ_ONLY ADMIN" "SUPER"
      ;;
    *)
      printf '%s\n%s\n%s\n' "READ_ONLY ADMIN" "SUPER" "BINLOG ADMIN"
      ;;
  esac
}
# Secondary fence GRANT clause body (excludes admin bypass and user-facing
# writes; aligned with roleProbe secondary fence post-alpha.61).
SWITCHOVER_SECONDARY_FENCE_GRANT_BODY='SELECT, PROCESS, RELOAD, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN'
# Explicit primary GRANT clause body used by `unfence_local_remote_root_for_primary`
# (rollback path) AND read by `remote_root_has_explicit_primary_grant` verifier.
# Verifier checks the "core write" subset (INSERT/UPDATE/DELETE/CREATE/DROP)
# is present; this body MUST contain that subset.
SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY='SELECT, INSERT, UPDATE, DELETE, CREATE, DROP, RELOAD, PROCESS, REFERENCES, INDEX, ALTER, SHOW DATABASES, CREATE TEMPORARY TABLES, LOCK TABLES, EXECUTE, REPLICATION SLAVE, REPLICATION CLIENT, REPLICATION MASTER ADMIN, CREATE VIEW, SHOW VIEW, CREATE ROUTINE, ALTER ROUTINE, EVENT, TRIGGER, CREATE USER'
# Core write privileges that MUST be present in primary grant for verifier to
# accept. Subset of SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY (alpha.62 invariant).
SWITCHOVER_PRIMARY_CORE_WRITE_PRIVS='INSERT|UPDATE|DELETE|CREATE|DROP'

append_switchover_trace() {
  local message="$*"
  local trace_file
  local trace_dir
  trace_file="${SWITCHOVER_TRACE_FILE:-${DATA_DIR}/log/switchover-action.log}"
  trace_dir=$(dirname "${trace_file}" 2>/dev/null || echo "")
  if [ -n "${trace_dir}" ]; then
    mkdir -p "${trace_dir}" 2>/dev/null || true
  fi
  if ! [ -d "${trace_dir}" ] || ! [ -w "${trace_dir}" ]; then
    trace_file="/tmp/switchover-action.log"
    trace_dir="/tmp"
  fi
  printf "%s %s\n" "$(date -u '+%Y-%m-%dT%H:%M:%SZ' 2>/dev/null || date)" "${message}" >>"${trace_file}" 2>/dev/null || true
}

log_switchover_info() {
  local message="$*"
  echo "${message}"
  append_switchover_trace "${message}"
}

log_switchover_error() {
  local message="$*"
  echo "${message}" >&2
  append_switchover_trace "${message}"
}

resolve_mariadb_client_bin() {
  if [ -n "${MARIADB_CLIENT_BIN}" ]; then
    if command -v "${MARIADB_CLIENT_BIN}" >/dev/null 2>&1; then
      command -v "${MARIADB_CLIENT_BIN}"
      return 0
    fi
    if [ -x "${MARIADB_CLIENT_BIN}" ]; then
      printf "%s" "${MARIADB_CLIENT_BIN}"
      return 0
    fi
    echo "Switchover failed: MARIADB_CLIENT_BIN=${MARIADB_CLIENT_BIN} is not executable; PATH=${PATH}" >&2
    return 1
  fi

  if [ -x "${MYSQL_CLIENT_DIR}/bin/mariadb" ]; then
    printf "%s" "${MYSQL_CLIENT_DIR}/bin/mariadb"
    return 0
  fi
  if command -v mariadb >/dev/null 2>&1; then
    command -v mariadb
    return 0
  fi

  echo "Switchover failed: mariadb client not found; checked ${MYSQL_CLIENT_DIR}/bin/mariadb and PATH=${PATH}" >&2
  return 1
}

setup_mariadb_client_bin() {
  local resolved
  resolved=$(resolve_mariadb_client_bin) || return 1
  MARIADB_CLIENT_BIN="${resolved}"
  export MARIADB_CLIENT_BIN
  log_switchover_info "Switchover using mariadb client: ${MARIADB_CLIENT_BIN}"
}

resolve_current_name() {
  if [ -n "${KB_SWITCHOVER_CURRENT_NAME}" ]; then
    echo "${KB_SWITCHOVER_CURRENT_NAME}"
    return 0
  fi
  echo "${POD_NAME:-}"
}

resolve_candidate_name() {
  local current_name
  current_name=$(resolve_current_name)
  if [ -n "${KB_SWITCHOVER_CANDIDATE_NAME}" ]; then
    echo "${KB_SWITCHOVER_CANDIDATE_NAME}"
    return 0
  fi

  local current_idx="${current_name##*-}"
  if [ "${current_idx}" = "0" ]; then
    echo "${CLUSTER_NAME}-${COMPONENT_NAME}-1"
  else
    echo "${CLUSTER_NAME}-${COMPONENT_NAME}-0"
  fi
}

resolve_candidate_fqdn() {
  local candidate
  candidate=$(resolve_candidate_name)
  echo "${candidate}.${CLUSTER_NAME}-${COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
}

resolve_primary_service_fqdn() {
  echo "${CLUSTER_NAME}-${COMPONENT_NAME}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}"
}

query_value() {
  local host="$1"
  local sql="$2"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${host}" -N -s -e "${sql}" 2>/dev/null || echo ""
}

run_sql() {
  local host="$1"
  local sql="$2"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${host}" -N -s -e "${sql}" >/dev/null 2>&1
}

run_sql_with_connect_timeout() {
  local host="$1"
  local connect_timeout="$2"
  local sql="$3"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${connect_timeout}" \
    -P3306 -h"${host}" -N -s -e "${sql}" >/dev/null 2>&1
}

run_local_internal_sql() {
  local sql="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "${sql}" >/dev/null 2>&1
}

run_local_maintenance_sql() {
  local sql="$1"
  run_local_internal_sql "${sql}" || run_sql "127.0.0.1" "${sql}"
}

run_local_sql_best_effort() {
  local sql="$1"
  run_local_maintenance_sql "${sql}" || true
}

query_local_value() {
  local sql="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "${sql}" 2>/dev/null
}

# alpha.89 v1 commit 7 (Helen 2026-05-19, C1 path topology merge) —
# read-only helper to detect whether semisync is currently enabled at
# runtime via the engine's in-memory @@rpl_semi_sync_master_enabled
# variable. Staged for future caller patches that need to decide
# whether to wait for semisync ACK during switchover or fall through
# immediately when the cluster is running in async mode under the
# merged CmpD.
#
# Return contract:
#   0 — semisync ON (@@rpl_semi_sync_master_enabled is 1 / ON / on)
#   1 — semisync OFF (@@rpl_semi_sync_master_enabled is 0 / OFF / off)
#   2 — undetermined: mariadb client failed, returned no row, or
#       returned a value outside the four recognized literals. Callers
#       MUST treat this as fail-closed by assuming semisync (do not
#       skip the safety wait) so a transient client failure does not
#       silently flip behavior to async during switchover.
#
# No caller wires this in commit 7. The helper is intentionally
# added without changing any call site so the existing switchover
# behavior is untouched on alpha.89; a focused follow-up commit will
# wire the helper into the specific stages that currently wait for
# semisync ACK and need to fall through under async mode.
#
# Connection context follows the surrounding query_local_value /
# run_local_internal_sql pattern: localhost on the chart's mariadbd
# port, user-facing root credentials read from the same env surface
# the rest of the switchover script already establishes. /bin/sh +
# busybox compatibility is the same as the surrounding helpers.
is_semisync_mode() {
  local val
  val=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s \
    -e "SELECT @@rpl_semi_sync_master_enabled" 2>/dev/null) || return 2
  case "${val}" in
    1|ON|on) return 0 ;;
    0|OFF|off) return 1 ;;
    *) return 2 ;;
  esac
}

sql_quote() {
  printf "%s" "$1" | sed "s/'/''/g"
}

query_slave_status() {
  local host="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${host}" -e "SHOW SLAVE STATUS\\G" 2>/dev/null || true
}

query_server_id() {
  local host="$1"
  query_value "${host}" "SELECT @@server_id;"
}

has_mariadb_client() {
  [ -x "${MARIADB_CLIENT_BIN}" ] || command -v "${MARIADB_CLIENT_BIN}" >/dev/null 2>&1
}

query_syncer_role() {
  local host="$1"
  "${SYNCERCTL_BIN}" --host "${host}" --port "${SYNCERCTL_PORT}" getrole 2>/dev/null | tr -d '\r\n'
}

remote_root_host_is_local() {
  case "${MARIADB_ROOT_HOST:-%}" in
    localhost|127.0.0.1|::1) return 0 ;;
    *) return 1 ;;
  esac
}

compute_grants_sha() {
  # alpha.62 v1 (Jack 04:08 tightening 1) / v2 (Jack 04:38 tightening): hash
  # tool fallback chain. Returns `<hash>|<algo>` where algo is one of
  # `sha256` / `sha1` / `md5` / `hash_tool_unavailable`. Caller MUST split
  # on `|` and emit two structured log fields:
  #   grants_sha=<hash|unavailable> reason_hash=<algo>
  # Hash failure NEVER influences fence judgment; field is for evidence
  # trace only. Empty value or single-token output is forbidden.
  local input="$1"
  local out
  if command -v sha256sum >/dev/null 2>&1; then
    out=$(printf '%s' "${input}" | sha256sum 2>/dev/null | awk '{print $1}')
    if [ -n "${out}" ]; then printf '%s|sha256' "${out}"; return 0; fi
  fi
  if command -v sha1sum >/dev/null 2>&1; then
    out=$(printf '%s' "${input}" | sha1sum 2>/dev/null | awk '{print $1}')
    if [ -n "${out}" ]; then printf '%s|sha1' "${out}"; return 0; fi
  fi
  if command -v md5sum >/dev/null 2>&1; then
    out=$(printf '%s' "${input}" | md5sum 2>/dev/null | awk '{print $1}')
    if [ -n "${out}" ]; then printf '%s|md5' "${out}"; return 0; fi
  fi
  printf 'unavailable|hash_tool_unavailable'
  return 0
}

split_grants_sha_field() {
  # Helper: given the raw `compute_grants_sha` output `<hash>|<algo>`, echo
  # `grants_sha=<hash> reason_hash=<algo>` on stdout. Caller pastes into
  # structured log line. Defensive: if input lacks `|`, echo
  # `grants_sha=unavailable reason_hash=hash_split_failed`.
  local raw="$1"
  case "${raw}" in
    *"|"*)
      local hash algo
      hash=$(printf '%s' "${raw}" | cut -d'|' -f1)
      algo=$(printf '%s' "${raw}" | cut -d'|' -f2)
      printf 'grants_sha=%s reason_hash=%s' "${hash}" "${algo}"
      ;;
    *)
      printf 'grants_sha=unavailable reason_hash=hash_split_failed'
      ;;
  esac
}

enumerate_user_facing_root_hosts() {
  # alpha.62 v1 (Jack 04:08 Blocker 1): single-source per-host enumeration of
  # user-facing root accounts via kb_internal_root view. Reuses alpha.60 v3
  # pattern: rc!=0 → fail-closed `root_host_query_failed` (NOT silent
  # root_account_not_found). Returns newline-separated host list to stdout
  # (may be empty if no root account exists). Caller must treat rc!=0 as
  # fatal — do NOT proceed with empty fallback.
  local root_user="${MARIADB_ROOT_USER:-root}"
  local hosts rc
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: enumerate_user_facing_root_hosts cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  hosts=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -B -s -e "SELECT Host FROM mysql.user WHERE User='${root_user}';" 2>&1)
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: enumerate_user_facing_root_hosts reason=root_host_query_failed user=${root_user} rc=${rc} stderr=${hosts}; fail-closed"
    return 1
  fi
  printf '%s' "${hosts}"
  return 0
}

_grants_for_host_via_internal() {
  # Read SHOW GRANTS FOR root@host via kb_internal_root view (avoids root
  # self-query loops where root may have lost SELECT on mysql).
  # Echoes grants stdout (may include 1141 stderr if no such grant). Sets caller
  # variable __GRANTS_RC via printf-on-stderr trick: instead, use 2>&1 + check rc.
  local root_user="${MARIADB_ROOT_USER:-root}"
  local host="$1"
  "${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR '${root_user}'@'${host}';" 2>&1
}

_local_root_write_probe_127() {
  # alpha.62 v1: TCP probe to 127.0.0.1 expecting fail (1044 priv-based or
  # 1290 read_only-based). Used only for the root@127.0.0.1 host since it
  # is the only host where the local probe attribution is deterministic.
  #
  # alpha.63 v1 (Jack 05:22 RED closeout I-2 + 05:24 instrumentation 1):
  # the legacy `printf '%s|%s|%s' rc|errno|out` returns broke when `out`
  # was multi-line (mariadb client wraps SQL stderr across lines). The
  # caller's `cut -d'|' -f2` then returned `errno\nfirst-line-of-stderr`
  # which never matched the `1044|1290|1142` case patterns, so a real
  # priv-based fence was misclassified as `probe_account_mismatch`.
  # Fix: write the three fields into module-scope global variables
  # __PROBE_RC / __PROBE_ERRNO / __PROBE_OUT instead of joining with `|`.
  # Caller MUST pre-clear the three globals before calling and post-
  # validate that __PROBE_RC is non-empty numeric and __PROBE_ERRNO is
  # one of the 5 valid values (1044/1290/1142/0/other) — fail-closed
  # `probe_result_malformed` / `probe_result_malformed_errno` otherwise
  # (Jack 05:24 instrumentation 1).
  #
  # alpha.127+ fix: replaced mutating INSERT/DELETE probe with read-only
  # SHOW GRANTS check to eliminate orphan GTID writes on the demoted primary.
  # Mirrors the pattern used by verify_post_dcs_local_root_write_fenced().
  __PROBE_OUT=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR '${MARIADB_ROOT_USER}'@'127.0.0.1';" 2>&1)
  __PROBE_RC=$?
  if [ "${__PROBE_RC}" -ne 0 ]; then
    case "${__PROBE_OUT}" in
      *1044*) __PROBE_ERRNO=1044 ;;
      *1141*) __PROBE_ERRNO=1044 ;;
      *) __PROBE_ERRNO=other ;;
    esac
    return
  fi
  if echo "${__PROBE_OUT}" | grep -qiE 'ALL PRIVILEGES|INSERT|UPDATE|DELETE|CREATE'; then
    __PROBE_ERRNO=0
  else
    __PROBE_ERRNO=1290
  fi
}

_filter_grants_keep_unmatched() {
  # alpha.63 v1 (Jack 05:24 instrumentation 2): emit only the grants lines
  # that do NOT match the line-anchored whitelist
  # SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN. Caller assigns the result via
  # `$(...)` command substitution. Audit-side count + dump are computed
  # by separate _count_grants_matched_whitelist / _dump_grants_matched_whitelist
  # callers — each its own subshell — to avoid the "globals do not survive
  # command substitution" pitfall.
  printf '%s\n' "$1" | awk -v pat="${SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN}" '!match($0, pat) { print }'
}

_count_grants_matched_whitelist() {
  # Counts how many lines of the input grants match the whitelist
  # (i.e., would be filtered out by _filter_grants_keep_unmatched). Echoes
  # an integer (always 0 or higher).
  local count
  count=$(printf '%s\n' "$1" | awk -v pat="${SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN}" 'match($0, pat){c++} END{print c+0}')
  case "${count}" in
    ''|*[!0-9]*) printf '0' ;;
    *) printf '%s' "${count}" ;;
  esac
}

_dump_grants_matched_whitelist() {
  # Echoes the lines of the input grants that match the whitelist (newline-
  # separated; no trailing newline guarantee).
  printf '%s\n' "$1" | awk -v pat="${SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN}" 'match($0, pat){print}'
}

_verify_host_is_fenced() {
  # alpha.62 v1 (Jack 04:08 Blocker 2 + Tightening 1): per-host verifier with
  # structured single-line log + grants_sha + probe_host attribution. Caller:
  # local_remote_root_is_fenced_for_secondary.
  local host="$1"
  local root_user="${MARIADB_ROOT_USER:-root}"
  local grants rc grants_sha_field bypass_residual="none" probe_host write_rc="skipped" write_errno="skipped" write_attempted="false"
  local reason=""
  # alpha.63 v1: initialize ignored-grants accounting at function entry so
  # all log lines (including the early grants-query-failed branch) include
  # the field. Set 0 here; _filter_grants_for_residual_scan re-sets later.
  __GRANTS_IGNORED_COUNT=0
  __GRANTS_IGNORED_LINES=""
  grants=$(_grants_for_host_via_internal "${host}")
  rc=$?
  grants_sha_field=$(split_grants_sha_field "$(compute_grants_sha "${grants}")")
  if [ "${rc}" -ne 0 ]; then
    case "${grants}" in
      *1141*|*"no such grant"*|*"There is no such grant"*)
        reason="account_grants_empty_or_1141"
        ;;
      *)
        reason="grants_query_failed"
        log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=none:grants_unavailable grants_query_rc=${rc} ${grants_sha_field} grants_bypass=unknown grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
        log_switchover_error "remote_root_fence_verify host=${host} grants_dump_begin"
        log_switchover_error "${grants}"
        log_switchover_error "remote_root_fence_verify host=${host} grants_dump_end"
        return 1
        ;;
    esac
    log_switchover_info "remote_root_fence_verify host=${host} verified_host=${host} probe_host=none:account_absent grants_query_rc=${rc} ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
    return 0
  fi
  # alpha.63 v1 (Jack 05:24 instrumentation 2): filter out the default
  # GRANT PROXY ... WITH GRANT OPTION row BEFORE the bypass / user-facing-
  # write residual scan. The whitelist pattern is line-anchored
  # (SWITCHOVER_GRANTS_IGNORED_LINE_PATTERN). Three independent subshell
  # helpers (each in its own `$(...)`) so the count + dump aren't lost to
  # the subshell-globals problem.
  local grants_filtered
  grants_filtered=$(_filter_grants_keep_unmatched "${grants}")
  __GRANTS_IGNORED_COUNT=$(_count_grants_matched_whitelist "${grants}")
  __GRANTS_IGNORED_LINES=$(_dump_grants_matched_whitelist "${grants}")
  # Detect any bypass priv residual (against filtered grants).
  bypass_residual=$(printf '%s' "${grants_filtered}" | grep -oE "${SWITCHOVER_BYPASS_PRIVILEGES_PATTERN}" | sort -u | tr '\n' ',' | sed 's/,$//')
  [ -z "${bypass_residual}" ] && bypass_residual="none"
  if [ "${bypass_residual}" != "none" ]; then
    reason="bypass_priv_residual:${bypass_residual}"
    log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=none:bypass_residual_short_circuit grants_query_rc=0 ${grants_sha_field} grants_bypass=${bypass_residual} grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
    log_switchover_error "remote_root_fence_verify host=${host} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "remote_root_fence_verify host=${host} grants_dump_end"
    if [ "${__GRANTS_IGNORED_COUNT}" -gt 0 ]; then
      log_switchover_error "remote_root_fence_verify host=${host} grants_ignored_dump_begin"
      log_switchover_error "${__GRANTS_IGNORED_LINES}"
      log_switchover_error "remote_root_fence_verify host=${host} grants_ignored_dump_end"
    fi
    return 1
  fi
  # Detect any user-facing write priv residual (against filtered grants).
  local write_residual
  write_residual=$(printf '%s' "${grants_filtered}" | grep -oE "${SWITCHOVER_USER_FACING_WRITE_PATTERN}" | sort -u | tr '\n' ',' | sed 's/,$//')
  if [ -n "${write_residual}" ]; then
    reason="bypass_priv_residual:${write_residual}"
    log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=none:write_priv_residual_short_circuit grants_query_rc=0 ${grants_sha_field} grants_bypass=${write_residual} grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
    log_switchover_error "remote_root_fence_verify host=${host} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "remote_root_fence_verify host=${host} grants_dump_end"
    if [ "${__GRANTS_IGNORED_COUNT}" -gt 0 ]; then
      log_switchover_error "remote_root_fence_verify host=${host} grants_ignored_dump_begin"
      log_switchover_error "${__GRANTS_IGNORED_LINES}"
      log_switchover_error "remote_root_fence_verify host=${host} grants_ignored_dump_end"
    fi
    return 1
  fi
  # alpha.63 v2 (Jack 08:36 v1 review HOLD blocker): contract from 05:26 says
  # "non-proxy WITH GRANT OPTION must fail-closed". v1 only removed the
  # GRANT OPTION literal token from SWITCHOVER_USER_FACING_WRITE_PATTERN;
  # input like `GRANT SELECT ON *.* TO 'root'@'%' WITH GRANT OPTION` (no
  # write priv name + GRANT OPTION token) was false-passing because neither
  # write_residual nor bypass_residual matched. Add an explicit
  # grant_option_residual check on the post-whitelist filtered grants:
  # any line with ` WITH GRANT OPTION` substring is non-proxy (PROXY rows
  # were already removed by the line-anchored whitelist) and MUST
  # fail-closed. Distinct reason `grant_option_residual` (NOT folded into
  # bypass_priv_residual) so closeout can grep specifically for this
  # token-level violation vs priv-name-level violations.
  local grant_option_residual_lines
  grant_option_residual_lines=$(printf '%s\n' "${grants_filtered}" | awk '/[ ]WITH GRANT OPTION/{print}')
  if [ -n "${grant_option_residual_lines}" ]; then
    reason="grant_option_residual"
    log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=none:grant_option_residual_short_circuit grants_query_rc=0 ${grants_sha_field} grants_bypass=GRANT_OPTION grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
    log_switchover_error "remote_root_fence_verify host=${host} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "remote_root_fence_verify host=${host} grants_dump_end"
    log_switchover_error "remote_root_fence_verify host=${host} grant_option_residual_dump_begin"
    log_switchover_error "${grant_option_residual_lines}"
    log_switchover_error "remote_root_fence_verify host=${host} grant_option_residual_dump_end"
    if [ "${__GRANTS_IGNORED_COUNT}" -gt 0 ]; then
      log_switchover_error "remote_root_fence_verify host=${host} grants_ignored_dump_begin"
      log_switchover_error "${__GRANTS_IGNORED_LINES}"
      log_switchover_error "remote_root_fence_verify host=${host} grants_ignored_dump_end"
    fi
    return 1
  fi
  # Probe scope: only deterministic for root@127.0.0.1.
  case "${host}" in
    "127.0.0.1")
      probe_host="127.0.0.1"
      write_attempted="true"
      # alpha.63 v1 (Jack 05:22 RED I-2 + 05:24 instrumentation 1):
      # pre-clear globals BEFORE the call (defends against stale value
      # reuse across multiple verifier invocations); call the probe
      # (which sets __PROBE_RC/__PROBE_ERRNO/__PROBE_OUT directly,
      # no pipe-separated parsing); post-validate the globals.
      __PROBE_RC=""
      __PROBE_ERRNO=""
      __PROBE_OUT=""
      _local_root_write_probe_127
      # Post-validate __PROBE_RC must be non-empty numeric.
      case "${__PROBE_RC}" in
        ''|*[!0-9]*)
          reason="probe_result_malformed"
          log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=true write_probe_rc=<malformed:${__PROBE_RC}> write_probe_errno=skipped reason=${reason}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_begin"
          log_switchover_error "${__PROBE_OUT}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_end"
          return 1
          ;;
      esac
      # Post-validate __PROBE_ERRNO must be in the 5-value valid set.
      case "${__PROBE_ERRNO}" in
        1044|1290|1142|0|other) ;;
        *)
          reason="probe_result_malformed_errno"
          log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=true write_probe_rc=${__PROBE_RC} write_probe_errno=<malformed:${__PROBE_ERRNO}> reason=${reason}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_begin"
          log_switchover_error "${__PROBE_OUT}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_end"
          return 1
          ;;
      esac
      write_rc="${__PROBE_RC}"
      write_errno="${__PROBE_ERRNO}"
      case "${write_errno}" in
        1044|1290|1142)
          reason="ok_by_local_probe:${write_errno}"
          log_switchover_info "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=true write_probe_rc=${write_rc} write_probe_errno=${write_errno} reason=${reason}"
          return 0
          ;;
        0)
          reason="writable_unexpected"
          log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=true write_probe_rc=${write_rc} write_probe_errno=${write_errno} reason=${reason}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_begin"
          log_switchover_error "${__PROBE_OUT}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_end"
          return 1
          ;;
        *)
          reason="probe_account_mismatch"
          log_switchover_error "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=true write_probe_rc=${write_rc} write_probe_errno=${write_errno} reason=${reason}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_begin"
          log_switchover_error "${__PROBE_OUT}"
          log_switchover_error "remote_root_fence_verify host=${host} probe_dump_end"
          return 1
          ;;
      esac
      ;;
    "localhost")
      probe_host="none:localhost_socket_not_attempted"
      reason="ok_by_grants_only:localhost_socket_not_attempted"
      log_switchover_info "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
      return 0
      ;;
    *)
      probe_host="none:wildcard_or_remote_not_locally_probable"
      reason="ok_by_grants_only:wildcard_or_remote_not_locally_probable"
      log_switchover_info "remote_root_fence_verify host=${host} verified_host=${host} probe_host=${probe_host} grants_query_rc=0 ${grants_sha_field} grants_bypass=none grants_ignored_count=${__GRANTS_IGNORED_COUNT} write_probe_attempted=false write_probe_rc=skipped write_probe_errno=skipped reason=${reason}"
      return 0
      ;;
  esac
}

_verify_host_has_explicit_primary_grant() {
  # alpha.62 v1 (Jack 04:08 DRIFT B + Tightening 3): per-host verifier for
  # rollback. Required: contains core write subset (INSERT/UPDATE/DELETE/
  # CREATE/DROP); rejects ALL PRIVILEGES; rejects admin bypass privileges.
  # Reads grants via kb_internal_root view. Structured single-line log.
  local host="$1"
  local root_user="${MARIADB_ROOT_USER:-root}"
  local grants rc grants_sha_field core_priv_present="none" bypass_residual="none" reason=""
  grants=$(_grants_for_host_via_internal "${host}")
  rc=$?
  grants_sha_field=$(split_grants_sha_field "$(compute_grants_sha "${grants}")")
  if [ "${rc}" -ne 0 ]; then
    case "${grants}" in
      *1141*|*"no such grant"*|*"There is no such grant"*)
        reason="account_grants_empty_or_1141"
        log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_query_rc=${rc} ${grants_sha_field} core_priv_present=none reason=${reason}"
        return 1
        ;;
      *)
        reason="grants_query_failed"
        log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_query_rc=${rc} ${grants_sha_field} core_priv_present=unknown reason=${reason}"
        log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_begin"
        log_switchover_error "${grants}"
        log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_end"
        return 1
        ;;
    esac
  fi
  # Reject ALL PRIVILEGES (legacy alpha.59-and-earlier residual).
  case "${grants}" in
    *"GRANT ALL PRIVILEGES ON *.*"*|*"ALL PRIVILEGES"*)
      reason="all_privileges_residual"
      log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_query_rc=0 ${grants_sha_field} core_priv_present=unknown reason=${reason}"
      log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_begin"
      log_switchover_error "${grants}"
      log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_end"
      return 1
      ;;
  esac
  # Reject admin bypass priv (excluding ALL PRIVILEGES which was caught above).
  # Local loopback/socket root may keep BINLOG ADMIN for chart-internal
  # sql_log_bin=0 paths; remote root must not keep it.
  local primary_bypass_pattern
  case "${host}" in
    "127.0.0.1"|"localhost")
      primary_bypass_pattern="READ_ONLY ADMIN|SUPER|CONNECTION ADMIN"
      ;;
    *)
      primary_bypass_pattern="READ_ONLY ADMIN|SUPER|BINLOG ADMIN|CONNECTION ADMIN"
      ;;
  esac
  bypass_residual=$(printf '%s' "${grants}" | grep -oE "${primary_bypass_pattern}" | sort -u | tr '\n' ',' | sed 's/,$//')
  if [ -n "${bypass_residual}" ]; then
    reason="admin_bypass_residual:${bypass_residual}"
    log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_query_rc=0 ${grants_sha_field} core_priv_present=unknown reason=${reason}"
    log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_end"
    return 1
  fi
  # Verify core write subset is present.
  core_priv_present=$(printf '%s' "${grants}" | grep -oE "${SWITCHOVER_PRIMARY_CORE_WRITE_PRIVS}" | sort -u | tr '\n' ',' | sed 's/,$//')
  [ -z "${core_priv_present}" ] && core_priv_present="none"
  # Count distinct core privs found.
  local core_count
  core_count=$(printf '%s\n' "${core_priv_present}" | tr ',' '\n' | grep -cE "^(INSERT|UPDATE|DELETE|CREATE|DROP)$" || true)
  if [ "${core_count}" -lt 5 ]; then
    reason="core_write_priv_missing:expected=INSERT,UPDATE,DELETE,CREATE,DROP got=${core_priv_present}"
    log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_query_rc=0 ${grants_sha_field} core_priv_present=${core_priv_present} reason=${reason}"
    log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "remote_root_explicit_primary_grant_verify host=${host} grants_dump_end"
    return 1
  fi
  reason="ok"
  log_switchover_info "remote_root_explicit_primary_grant_verify host=${host} grants_query_rc=0 ${grants_sha_field} core_priv_present=${core_priv_present} reason=${reason}"
  return 0
}

candidate_remote_root_has_explicit_primary_grant() {
  # Same contract as remote_root_has_explicit_primary_grant(), but read through
  # the candidate's user-facing remote root session. This keeps the first
  # switchover from returning success while the promoted primary is still in the
  # secondary-fence grant shape, which would make the next switchback fail in
  # rollback.
  local candidate_fqdn="$1"
  local label="${2:-candidate-remote-root-primary-ready}"
  local grants rc grants_sha_field core_priv_present="none" bypass_residual="none" reason=""

  remote_root_host_is_local && return 0
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_query_rc=unavailable core_priv_present=unknown reason=mariadb_client_unavailable"
    return 1
  fi

  grants=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h"${candidate_fqdn}" -N -s -e "SHOW GRANTS FOR CURRENT_USER;" 2>&1)
  rc=$?
  grants_sha_field=$(split_grants_sha_field "$(compute_grants_sha "${grants}")")
  if [ "${rc}" -ne 0 ]; then
    reason="grants_query_failed"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_query_rc=${rc} ${grants_sha_field} core_priv_present=unknown reason=${reason}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_end"
    return 1
  fi

  case "${grants}" in
    *"GRANT ALL PRIVILEGES ON *.*"*|*"ALL PRIVILEGES"*)
      reason="all_privileges_residual"
      log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_query_rc=0 ${grants_sha_field} core_priv_present=unknown reason=${reason}"
      log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_begin"
      log_switchover_error "${grants}"
      log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_end"
      return 1
      ;;
  esac

  bypass_residual=$(printf '%s' "${grants}" | grep -oE "READ_ONLY ADMIN|SUPER|BINLOG ADMIN|CONNECTION ADMIN" | sort -u | tr '\n' ',' | sed 's/,$//')
  if [ -n "${bypass_residual}" ]; then
    reason="admin_bypass_residual:${bypass_residual}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_query_rc=0 ${grants_sha_field} core_priv_present=unknown reason=${reason}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_end"
    return 1
  fi

  core_priv_present=$(printf '%s' "${grants}" | grep -oE "${SWITCHOVER_PRIMARY_CORE_WRITE_PRIVS}" | sort -u | tr '\n' ',' | sed 's/,$//')
  [ -z "${core_priv_present}" ] && core_priv_present="none"
  local core_count
  core_count=$(printf '%s\n' "${core_priv_present}" | tr ',' '\n' | grep -cE "^(INSERT|UPDATE|DELETE|CREATE|DROP)$" || true)
  if [ "${core_count}" -lt 5 ]; then
    reason="core_write_priv_missing:expected=INSERT,UPDATE,DELETE,CREATE,DROP got=${core_priv_present}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_query_rc=0 ${grants_sha_field} core_priv_present=${core_priv_present} reason=${reason}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_begin"
    log_switchover_error "${grants}"
    log_switchover_error "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_dump_end"
    return 1
  fi

  reason="ok"
  log_switchover_info "candidate_remote_root_explicit_primary_grant_verify label=${label} host=${candidate_fqdn} grants_query_rc=0 ${grants_sha_field} core_priv_present=${core_priv_present} reason=${reason}"
  return 0
}

remote_root_has_explicit_primary_grant() {
  # alpha.62 v1 (Jack 04:08 review DRIFT B): replaced legacy full-access
  # rollback verifier (which required GRANT ALL PRIVILEGES). Since alpha.60
  # v2 unfence_local_remote_root_for_primary no longer grants ALL PRIVILEGES
  # — it grants the explicit non-bypass primary list — the legacy verifier
  # was guaranteed to fail-close any rollback. The new verifier:
  #   * iterates over per-host enumeration (kb_internal_root view)
  #   * for each host: SHOW GRANTS, must contain the core-write subset
  #     (INSERT/UPDATE/DELETE/CREATE/DROP), must NOT contain GRANT ALL
  #     PRIVILEGES, must NOT contain admin bypass privileges
  #   * structured per-host log; full grants dump after sentinel line
  # Caller pattern: rollback_current_primary_switchover_guard.
  local host_list_arg="${1:-}"
  local host_list_source host_list_sha
  local host total_hosts=0 ok_hosts=0 failed_hosts=0
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: rollback verifier remote_root_has_explicit_primary_grant cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  if [ -n "${host_list_arg}" ]; then
    host_list_source="${host_list_arg}"
    host_list_sha=$(compute_grants_sha "${host_list_arg}")
    log_switchover_info "Rollback verifier remote_root_has_explicit_primary_grant: using caller-provided host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_arg}" | wc -l | tr -d ' ')"
  else
    host_list_source=$(enumerate_user_facing_root_hosts) || return 1
    if [ -z "${host_list_source}" ]; then
      log_switchover_error "Rollback verifier remote_root_has_explicit_primary_grant: reason=root_account_not_found user=${MARIADB_ROOT_USER}; fail-closed (rollback expects user-facing root to exist)"
      return 1
    fi
    host_list_sha=$(compute_grants_sha "${host_list_source}")
    log_switchover_info "Rollback verifier remote_root_has_explicit_primary_grant: enumerated host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_source}" | wc -l | tr -d ' ')"
  fi
  while IFS= read -r host; do
    [ -z "${host}" ] && continue
    total_hosts=$((total_hosts + 1))
    if _verify_host_has_explicit_primary_grant "${host}"; then
      ok_hosts=$((ok_hosts + 1))
    else
      failed_hosts=$((failed_hosts + 1))
    fi
  done <<EOF_HOSTS
${host_list_source}
EOF_HOSTS
  log_switchover_info "Rollback verifier remote_root_has_explicit_primary_grant summary total=${total_hosts} ok=${ok_hosts} failed=${failed_hosts}"
  [ "${failed_hosts}" -eq 0 ] && [ "${total_hosts}" -gt 0 ]
}

remote_root_primary_ready() {
  local host="$1"
  local label="${2:-candidate-remote-root-primary-ready}"
  local read_only
  remote_root_host_is_local && return 0
  read_only=$(query_value "${host}" "SELECT @@global.read_only;")
  case "${read_only}" in
    0|OFF|off)
      candidate_remote_root_has_explicit_primary_grant "${host}" "${label}" || return 1
      log_switchover_info "Switchover candidate remote root primary-readiness probe label=${label} host=${host} read_only=${read_only} rc=0"
      return 0
      ;;
  esac
  [ -z "${read_only}" ] && read_only="<empty>"
  log_switchover_error "Switchover candidate remote root primary-readiness probe label=${label} host=${host} read_only=${read_only} rc=1"
  return 1
}

syncer_role_is() {
  local host="$1"
  local expected="$2"
  local role
  [ -x "${SYNCERCTL_BIN}" ] || command -v "${SYNCERCTL_BIN}" >/dev/null 2>&1 || return 1
  role="$(query_syncer_role "${host}")"
  [ "${role}" = "${expected}" ]
}

fence_local_remote_root_for_secondary() {
  # alpha.62 v1 (Jack 04:08 DRIFT A + Blocker 1): per-host enumeration replaces
  # the legacy single-host (root@%) fence. Removes the legacy optional
  # secondary admin grant helper entirely (it was granting BINLOG ADMIN /
  # CONNECTION ADMIN / READ_ONLY ADMIN immediately after fence, defeating
  # alpha.61's tightening on the same callsite).
  #
  # Single-source GRANT body: SWITCHOVER_SECONDARY_FENCE_GRANT_BODY (top of
  # file). Per-host: REVOKE ALL + GRANT body + post-revoke residual check
  # (rejects bypass + user-facing write privs). Aligned with alpha.60 v3
  # post-DCS revoke pattern.
  #
  # Caller passes host_list (preferred); if not, query and detect drift.
  local host_list_arg="${1:-}"
  local host_list_source host_list_sha
  local user host password sql out rc
  local total_hosts=0 ok_hosts=0 failed_hosts=0
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: fence_local_remote_root_for_secondary cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  password=$(sql_quote "${MARIADB_ROOT_PASSWORD}")
  if [ -n "${host_list_arg}" ]; then
    host_list_source="${host_list_arg}"
    host_list_sha=$(compute_grants_sha "${host_list_arg}")
    log_switchover_info "fence_local_remote_root_for_secondary: using caller-provided host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_arg}" | wc -l | tr -d ' ')"
  else
    host_list_source=$(enumerate_user_facing_root_hosts) || return 1
    host_list_sha=$(compute_grants_sha "${host_list_source}")
    log_switchover_info "fence_local_remote_root_for_secondary: enumerated host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_source}" | wc -l | tr -d ' ')"
    # Defensive drift detection: re-query and compare sha.
    local host_list_recheck recheck_sha
    host_list_recheck=$(enumerate_user_facing_root_hosts) || return 1
    recheck_sha=$(compute_grants_sha "${host_list_recheck}")
    if [ "${host_list_sha}" != "${recheck_sha}" ]; then
      log_switchover_error "Switchover failed: fence_local_remote_root_for_secondary reason=root_host_list_drift sha_initial=${host_list_sha} sha_current=${recheck_sha}; fail-closed"
      return 1
    fi
  fi
  while IFS= read -r host; do
    [ -z "${host}" ] && continue
    total_hosts=$((total_hosts + 1))
    local quoted_host
    quoted_host=$(sql_quote "${host}")
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${quoted_host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${quoted_host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${quoted_host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${quoted_host}';
      GRANT ${SWITCHOVER_SECONDARY_FENCE_GRANT_BODY} ON *.* TO '${user}'@'${quoted_host}';
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
    out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "${sql}" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      log_switchover_error "fence_local_remote_root_for_secondary: host=${host} fence_apply_rc=${rc} stderr=${out}; fail-closed"
      failed_hosts=$((failed_hosts + 1))
      continue
    fi
    log_switchover_info "fence_local_remote_root_for_secondary: host=${host} fence_apply_rc=0"
    # Post-fence residual check via per-host verifier.
    if _verify_host_is_fenced "${host}"; then
      ok_hosts=$((ok_hosts + 1))
    else
      failed_hosts=$((failed_hosts + 1))
    fi
  done <<EOF_HOSTS
${host_list_source}
EOF_HOSTS
  log_switchover_info "fence_local_remote_root_for_secondary summary total=${total_hosts} ok=${ok_hosts} failed=${failed_hosts}"
  if [ "${total_hosts}" -eq 0 ]; then
    log_switchover_error "fence_local_remote_root_for_secondary: reason=root_account_not_found user=${MARIADB_ROOT_USER}; fail-closed"
    return 1
  fi
  [ "${failed_hosts}" -eq 0 ]
}

disconnect_local_remote_root_sessions_for_secondary() {
  local user ids id killed=0 skipped=0
  remote_root_host_is_local && return 0
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  ids=$(query_local_value "
    SELECT IFNULL(GROUP_CONCAT(ID SEPARATOR ' '), '')
      FROM information_schema.PROCESSLIST
     WHERE USER='${user}'
       AND ID <> CONNECTION_ID()
       AND HOST NOT LIKE 'localhost%'
       AND HOST NOT LIKE '127.0.0.1%'
       AND HOST NOT LIKE '::1%';
  ") || return 1
  if [ -z "${ids}" ]; then
    log_switchover_info "Switchover pre-DCS guard: no active remote root sessions to disconnect"
    return 0
  fi
  log_switchover_info "Switchover pre-DCS guard: disconnecting active remote root sessions ${ids}"
  for id in ${ids}; do
    case "${id}" in
      ''|*[!0-9]*)
        skipped=$((skipped + 1))
        continue
        ;;
    esac
    run_local_sql_best_effort "KILL CONNECTION ${id};"
    killed=$((killed + 1))
  done
  log_switchover_info "Switchover pre-DCS guard: remote root session disconnect issued killed=${killed} skipped=${skipped}"
  return 0
}

local_remote_root_is_fenced_for_secondary() {
  # alpha.62 v1 (Jack 04:08 DRIFT C + Blocker 1+2 + Tightening 1): per-host
  # iteration via kb_internal_root view + structured single-line log per host
  # + probe_host attribution. Caller passes host_list (preferred); fallback
  # query path detects drift.
  local host_list_arg="${1:-}"
  local host_list_source host_list_sha
  local host total_hosts=0 ok_hosts=0 failed_hosts=0
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: local_remote_root_is_fenced_for_secondary cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  if [ -n "${host_list_arg}" ]; then
    host_list_source="${host_list_arg}"
    host_list_sha=$(compute_grants_sha "${host_list_arg}")
    log_switchover_info "local_remote_root_is_fenced_for_secondary: using caller-provided host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_arg}" | wc -l | tr -d ' ')"
  else
    host_list_source=$(enumerate_user_facing_root_hosts) || return 1
    host_list_sha=$(compute_grants_sha "${host_list_source}")
    log_switchover_info "local_remote_root_is_fenced_for_secondary: enumerated host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_source}" | wc -l | tr -d ' ')"
    local host_list_recheck recheck_sha
    host_list_recheck=$(enumerate_user_facing_root_hosts) || return 1
    recheck_sha=$(compute_grants_sha "${host_list_recheck}")
    if [ "${host_list_sha}" != "${recheck_sha}" ]; then
      log_switchover_error "Switchover failed: local_remote_root_is_fenced_for_secondary reason=root_host_list_drift sha_initial=${host_list_sha} sha_current=${recheck_sha}; fail-closed"
      return 1
    fi
  fi
  while IFS= read -r host; do
    [ -z "${host}" ] && continue
    total_hosts=$((total_hosts + 1))
    if _verify_host_is_fenced "${host}"; then
      ok_hosts=$((ok_hosts + 1))
    else
      failed_hosts=$((failed_hosts + 1))
    fi
  done <<EOF_HOSTS
${host_list_source}
EOF_HOSTS
  log_switchover_info "local_remote_root_is_fenced_for_secondary summary total=${total_hosts} ok=${ok_hosts} failed=${failed_hosts}"
  if [ "${total_hosts}" -eq 0 ]; then
    log_switchover_error "local_remote_root_is_fenced_for_secondary: reason=root_account_not_found user=${MARIADB_ROOT_USER}; fail-closed"
    return 1
  fi
  [ "${failed_hosts}" -eq 0 ]
}

unfence_local_remote_root_for_primary() {
  # alpha.60 v2 (Jack 23:52 review point 2): rollback path must NOT re-grant
  # admin bypass privileges (READ_ONLY ADMIN / SUPER / BINLOG ADMIN) to user-
  # facing root. Grant the same explicit non-bypass privilege list that the
  # roleProbe primary path uses, so a future switchover's post-DCS fence still
  # works after rollback. GRANT OPTION is in the trailing WITH clause only.
  #
  # alpha.62 v1 (Jack 04:08 Tightening 3): GRANT body now sourced from the
  # shared constant SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY (top of file). The
  # rollback verifier remote_root_has_explicit_primary_grant reads from the
  # same constant via SWITCHOVER_PRIMARY_CORE_WRITE_PRIVS subset; ShellSpec
  # strong-binds to prevent drift. Per-host enumeration applied (Blocker 1).
  local host_list_arg="${1:-}"
  local host_list_source host_list_sha
  local user host password sql out rc
  local total_hosts=0 ok_hosts=0 failed_hosts=0
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: unfence_local_remote_root_for_primary cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  user=$(sql_quote "${MARIADB_ROOT_USER}")
  password=$(sql_quote "${MARIADB_ROOT_PASSWORD}")
  if [ -n "${host_list_arg}" ]; then
    host_list_source="${host_list_arg}"
    host_list_sha=$(compute_grants_sha "${host_list_arg}")
    log_switchover_info "unfence_local_remote_root_for_primary: using caller-provided host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_arg}" | wc -l | tr -d ' ')"
  else
    host_list_source=$(enumerate_user_facing_root_hosts) || return 1
    host_list_sha=$(compute_grants_sha "${host_list_source}")
    log_switchover_info "unfence_local_remote_root_for_primary: enumerated host list sha=${host_list_sha} hosts_count=$(printf '%s\n' "${host_list_source}" | wc -l | tr -d ' ')"
  fi
  while IFS= read -r host; do
    [ -z "${host}" ] && continue
    total_hosts=$((total_hosts + 1))
    local quoted_host
    quoted_host=$(sql_quote "${host}")
    sql="
      SET SESSION sql_log_bin=0;
      CREATE USER IF NOT EXISTS '${user}'@'${quoted_host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${quoted_host}' IDENTIFIED BY '${password}';
      ALTER USER '${user}'@'${quoted_host}' ACCOUNT UNLOCK;
      REVOKE ALL PRIVILEGES, GRANT OPTION FROM '${user}'@'${quoted_host}';
      GRANT ${SWITCHOVER_EXPLICIT_PRIMARY_GRANT_BODY} ON *.* TO '${user}'@'${quoted_host}' WITH GRANT OPTION;
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    "
    out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "${sql}" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      log_switchover_error "unfence_local_remote_root_for_primary: host=${host} unfence_apply_rc=${rc} stderr=${out}; fail-closed"
      failed_hosts=$((failed_hosts + 1))
      continue
    fi
    log_switchover_info "unfence_local_remote_root_for_primary: host=${host} unfence_apply_rc=0"
    ok_hosts=$((ok_hosts + 1))
  done <<EOF_HOSTS
${host_list_source}
EOF_HOSTS
  log_switchover_info "unfence_local_remote_root_for_primary summary total=${total_hosts} ok=${ok_hosts} failed=${failed_hosts}"
  if [ "${total_hosts}" -eq 0 ]; then
    log_switchover_error "unfence_local_remote_root_for_primary: reason=root_account_not_found user=${MARIADB_ROOT_USER}; fail-closed"
    return 1
  fi
  [ "${failed_hosts}" -eq 0 ]
}

set_local_read_only() {
  local value="$1"
  run_local_maintenance_sql "SET GLOBAL read_only=${value};"
}

local_read_only_is() {
  local expected="$1"
  local actual
  actual=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  [ "${actual}" = "${expected}" ]
}

rollback_current_primary_switchover_guard() {
  # alpha.62 v1 (Jack 04:08 DRIFT B + Blocker 1): rollback path now passes
  # host_list to unfence + verifier, both read same per-host enumeration.
  # Legacy full-access rollback verifier renamed to
  # remote_root_has_explicit_primary_grant — see that function's comment.
  #
  # alpha.80 v1 (Helen): the alpha.76 `.switchover-fence-active` marker
  # clear call here has been removed — alpha.79 v1 minimalist deleted the
  # marker writer in prepare, so there is nothing to clear. Pure dead-code
  # cleanup, no runtime behavior change.
  local failed=0
  local host_list=""
  log_switchover_info "Switchover rollback: restoring current primary write access after pre-DCS failure"
  # Best-effort host list capture; if enumeration fails here we still attempt
  # rollback (rollback fails via unfence/verifier rather than blocking on
  # enumeration). Empty host_list means downstream functions fall back to
  # their own enumeration with drift detection.
  host_list=$(enumerate_user_facing_root_hosts 2>/dev/null) || host_list=""
  if ! set_local_read_only "OFF"; then
    log_switchover_error "Switchover rollback failed: could not set current primary read_only=OFF"
    failed=1
  fi
  if ! unfence_local_remote_root_for_primary "${host_list}"; then
    log_switchover_error "Switchover rollback failed: could not restore current primary remote root grants"
    failed=1
  fi
  if ! local_read_only_is "0"; then
    log_switchover_error "Switchover rollback failed: current primary read_only did not return to 0"
    failed=1
  fi
  if ! remote_root_has_explicit_primary_grant "${host_list}"; then
    log_switchover_error "Switchover rollback failed: current primary remote root grants do not match explicit primary grant contract"
    failed=1
  fi
  [ "${failed}" -eq 0 ]
}

prepare_current_primary_for_switchover() {
  # alpha.79 v1 (Helen TL, per westonnnn 21:50 `48a132e2`/`b9a62176`
  # directive: "学 MySQL semisync 的极简思路，来改，现在 / 改完之后再测"):
  # The pre-DCS REMOTE root fence chain (fence_local_remote_root_for_secondary
  # + local_remote_root_is_fenced_for_secondary + _verify_host_is_fenced)
  # introduced in alpha.61 is the SOURCE of the race that alpha.75/.76/.77/
  # .78 chased without 100% closing (alpha.78 v1 N=3 = 2 GREEN / 1 RED with
  # same-type race reopened on n1ab 2026-05-14 13:27:33Z; trace shows
  # grants_sha SECONDARY→PRIMARY flip in the 1s between inner verify and
  # outer verify).
  #
  # The MySQL semisync addon (research 2026-05-14 by Explore agent) does
  # NOT modify root@'%' grants during switchover at all. It relies on:
  #   1. read_only=1 set on the demoted primary post-DCS swap
  #   2. semi-sync ACK protocol blocking commits
  #   3. user-facing root account NOT holding any read_only-bypass privilege
  #      (SUPER / READ_ONLY ADMIN everywhere, BINLOG ADMIN on non-local hosts),
  #      which is the alpha.61 hard contract that MariaDB has already adopted
  #      and we are KEEPING
  #
  # alpha.79 v1 short-circuits this function to a no-op. The post-DCS local-
  # root write fence verifier (verify_post_dcs_local_root_write_fenced)
  # remains the gatekeeper for "read_only=1 is effective on user-facing
  # root" — that verifier reads INSERT/UPDATE rejection at 1290 errno, NOT
  # grant state, so it remains race-free.
  #
  # alpha.80 v1 (Helen): the alpha.76/.77/.78 marker helpers
  # (write_switchover_fence_active_marker / clear_switchover_fence_active_
  # marker / switchover_fence_active_marker_file) are now removed entirely.
  # The roleprobe.sh + cmpd-semisync.yaml consumer checks are also removed.
  # All pure dead-code cleanup, no runtime behavior change.
  log_switchover_info "Switchover pre-DCS guard (alpha.79 v1 minimalist): skipping per-host root@'%' fence; relying on post-DCS read_only=1 + semisync ACK + alpha.61 admin-bypass priv contract"
  return 0
}

revoke_user_facing_root_admin_privileges_for_secondary() {
  # alpha.60 v2 hard contract (Jack 23:52 v2 blocker review):
  # Each bypass privilege MUST be revoked individually so 1141 on one cannot
  # mask the continued presence of others. After all per-privilege REVOKEs for
  # a host, we re-issue SHOW GRANTS and assert no bypass privilege remains;
  # if one does, this host is fail-closed (`revoke_residual_bypass`). 1141
  # on a single privilege only marks THAT privilege already-fenced - never
  # the host as a whole.
  #
  # post-DCS read_only=ON does not fence user-facing root that holds READ_ONLY
  # ADMIN / SUPER. It also does not fence non-local root hosts that hold BINLOG
  # ADMIN, so remote root@'%' must lose BINLOG ADMIN. Local root@localhost and
  # root@127.0.0.1 may keep BINLOG ADMIN because chart-internal loopback/socket
  # paths need SET sql_log_bin=0 and BINLOG ADMIN alone does not bypass
  # @@global.read_only. kb_internal_root is intentionally OUT of scope (it must
  # keep READ_ONLY ADMIN for secondary-side 1062 repair in the alpha.59
  # secondary roleProbe path).
  local root_user="${MARIADB_ROOT_USER:-root}"
  local hosts host grants out rc
  local total_revoked=0 total_already_fenced=0 total_failed_hosts=0
  local snapshot
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  # alpha.60 v3 (Jack 00:08 review): the host enumeration query MUST distinguish
  # "rc=0 with empty stdout" (genuinely no root account) from "rc!=0" (query
  # itself failed for permission/connection/SQL reasons). Treating both as
  # `root_account_not_found` is a class 1 silent fallback that lets the
  # function pretend coverage. If the enumeration fails, fail-closed.
  hosts=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -B -s -e "SELECT Host FROM mysql.user WHERE User='${root_user}';" 2>&1)
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke: reason=root_host_query_failed user=${root_user} rc=${rc} stderr=${hosts}; fail-closed"
    return 1
  fi
  if [ -z "${hosts}" ]; then
    log_switchover_info "Switchover post-DCS root revoke: reason=root_account_not_found user=${root_user} skip (rc=0)"
    return 0
  fi
  while IFS= read -r host; do
    [ -z "${host}" ] && continue
    local host_failed=0 host_revoked=0 host_already=0
    grants=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR '${root_user}'@'${host}';" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      case "${grants}" in
        *1141*|*"no such grant"*|*"There is no such grant"*)
          log_switchover_info "Switchover post-DCS root revoke: reason=privilege_absent_already_fenced ${root_user}@${host} (1141 from SHOW GRANTS)"
          total_already_fenced=$((total_already_fenced + 1))
          continue
          ;;
        *)
          log_switchover_error "Switchover failed: post-DCS root revoke: reason=show_grants_failed ${root_user}@${host} rc=${rc} out=${grants}"
          total_failed_hosts=$((total_failed_hosts + 1))
          continue
          ;;
      esac
    fi
    # Per-privilege REVOKE. 1141 on one priv is local-skip, NEVER host-wide.
    local priv privs
    privs=$(root_post_dcs_revoke_privilege_list_for_host "${host}")
    while IFS= read -r priv; do
      [ -z "${priv}" ] && continue
      out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
        --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
        -P3306 -h127.0.0.1 -N -s -e "
          SET SESSION sql_log_bin=0;
          REVOKE ${priv} ON *.* FROM '${root_user}'@'${host}';
          SET SESSION sql_log_bin=1;
        " 2>&1)
      rc=$?
      if [ "${rc}" -eq 0 ]; then
        log_switchover_info "Switchover post-DCS root revoke: reason=revoked ${root_user}@${host} priv=${priv}"
        host_revoked=$((host_revoked + 1))
      else
        case "${out}" in
          *1141*|*"no such grant"*|*"There is no such grant"*)
            log_switchover_info "Switchover post-DCS root revoke: reason=privilege_absent_already_fenced ${root_user}@${host} priv=${priv} (1141 on REVOKE)"
            host_already=$((host_already + 1))
            ;;
          *)
            log_switchover_error "Switchover failed: post-DCS root revoke: reason=revoke_failed ${root_user}@${host} priv=${priv} rc=${rc} out=${out}"
            host_failed=$((host_failed + 1))
          ;;
        esac
      fi
    done <<EOF_PRIVS
${privs}
EOF_PRIVS
    # Per-host post-revoke residual check. If any bypass priv survived,
    # the host is fail-closed regardless of per-priv counts.
    grants=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR '${root_user}'@'${host}';" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      case "${grants}" in
        *1141*|*"no such grant"*|*"There is no such grant"*)
          log_switchover_info "Switchover post-DCS root revoke: reason=privilege_absent_already_fenced ${root_user}@${host} (post-revoke SHOW GRANTS 1141)"
          ;;
        *)
          log_switchover_error "Switchover failed: post-DCS root revoke: reason=post_revoke_show_grants_failed ${root_user}@${host} rc=${rc} out=${grants}"
          host_failed=$((host_failed + 1))
          ;;
      esac
    else
      if printf '%s\n' "${grants}" | grep -qE "$(root_read_only_bypass_pattern_for_host "${host}")"; then
        log_switchover_error "Switchover failed: post-DCS root revoke: reason=revoke_residual_bypass ${root_user}@${host} disallowed_privs=$(root_read_only_bypass_label_for_host "${host}") grants=${grants}"
        host_failed=$((host_failed + 1))
      fi
    fi
    if [ "${host_failed}" -gt 0 ]; then
      total_failed_hosts=$((total_failed_hosts + 1))
    fi
    total_revoked=$((total_revoked + host_revoked))
    total_already_fenced=$((total_already_fenced + host_already))
  done <<EOF_HOSTS
${hosts}
EOF_HOSTS
  if [ "${total_failed_hosts}" -gt 0 ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke summary revoked=${total_revoked} already_fenced=${total_already_fenced} failed_hosts=${total_failed_hosts}; fail-closed"
    return 1
  fi
  # alpha.111 P0a URGENT Phase 2 root cause fix: wrap FLUSH PRIVILEGES in
  # SET SESSION sql_log_bin=0/1 to prevent orphan binlog event emission on
  # demoted-primary post-switchover binlog. Round 1c-H Track A async CM4
  # evidence (Jack mysqlbinlog dump on mdb-async-9391 pod-0 @11:30:06Z)
  # identified a domain-1 FLUSH PRIVILEGES event that became orphan post-CM4
  # switchover (pod-1 promoted primary at domain-1 seq=153, pod-0 demoted
  # secondary had local domain-1 seq=154 — the extra event was this bare
  # FLUSH PRIVILEGES emit). kb_internal_root has BINLOG ADMIN per alpha.66+
  # so SET sql_log_bin=0 succeeds; FLUSH PRIVILEGES still executes against
  # local mysql.user but emit to binlog suppressed.
  out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -s -e "
      SET SESSION sql_log_bin=0;
      FLUSH PRIVILEGES;
      SET SESSION sql_log_bin=1;
    " 2>&1)
  rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: post-DCS root revoke: FLUSH PRIVILEGES failed rc=${rc} out=${out}; fail-closed"
    return 1
  fi
  snapshot=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
    --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
    -P3306 -h127.0.0.1 -N -B -s -e "
      SELECT CONCAT('user=', User, '@', Host) FROM mysql.user WHERE User='${root_user}';
    " 2>/dev/null | tr '\n' ' ' || true)
  log_switchover_info "Switchover post-DCS root revoke summary revoked=${total_revoked} already_fenced=${total_already_fenced} failed_hosts=0; snapshot=[${snapshot}]"
  return 0
}

verify_post_dcs_local_root_write_fenced() {
  # alpha.105 (Jack 2026-05-29) verifier rewrite — destructive write check
  # removed; replaced with read-only privilege query against user-facing root
  # accounts. Reason: the alpha.59-104 verifier body issued an INSERT into
  # kubeblocks.kb_post_dcs_fence_probe as user-facing root to test whether
  # @@global.read_only=ON actually rejects user-facing writes. Under a real
  # bypass condition (post-DCS root revoke ran but only stripped READ_ONLY
  # ADMIN / SUPER / remote BINLOG ADMIN, leaving INSERT/UPDATE/DELETE on
  # user-facing root), this INSERT SUCCEEDED, was binlogged on the demoted
  # primary, and the new primary (already promoted in DCS) never replicated
  # it back. That single INSERT became a permanent orphan event and the
  # subsequent rejoin attempt hit GTID divergence fail-closed — the verifier
  # itself was the source of the orphan it then detected. Live reproduction
  # task442-full-n1-alpha104-r1c-fullrun-0428 async CM4 confirmed the
  # self-referential cycle: pod-0 binlog gtid_binlog_pos=1-1-175, pod-1
  # gtid_binlog_pos=1-1-174,2-2-N, both `kubeblocks.kb_post_dcs_fence_probe`
  # rows show ts=20:50:50Z (the verifier's own write). Evidence sha256
  # a48ab90d13da5740a7899ba6e28657671534352f9c6000bd15b32bcf048275c9.
  #
  # The verifier purpose stands: confirm user-facing root cannot bypass the
  # post-DCS read_only=ON fence. The new implementation enumerates SHOW
  # GRANTS for root@'%' / root@'127.0.0.1' / root@'localhost' (the same
  # host set apply_post_dcs_root_revoke iterates) and scans for any of the
  # read_only-bypass privileges that the revoke step claims to have removed
  # (READ_ONLY ADMIN / SUPER everywhere, BINLOG ADMIN only on non-local root
  # hosts, plus a defensive ALL PRIVILEGES match). If any bypass-class
  # privilege is still granted, the
  # fence is by definition not enforced; otherwise the contract holds. The
  # query produces zero binlog events and zero observable side effects on
  # data, replication topology, or DCS state, eliminating the self-pollution
  # path. The session connects as MARIADB_INTERNAL_ROOT_USER (kb_internal_
  # root) because user-facing root@'localhost' is the very subject under
  # test and may itself have been narrowed past SELECT on mysql.* — using
  # the internal admin keeps the query unambiguously read-only at the
  # privilege-system level (per Lily Doc B Rule 4(d): "诊断账号不得拥有
  # 可绕过被测 gate 的特权" — true here because the diagnostic is
  # SHOW GRANTS, not the gate operation itself).
  #
  # Acceptance contract (rewrite):
  #   - rc=0 + grants contain no host-disallowed bypass privilege
  #     (local BINLOG ADMIN is allowed; remote BINLOG ADMIN is not)    → PASS
  #   - rc=0 + grants contain any bypass-class privilege               → FAIL
  #     (fence not enforced; user-facing root can still bypass read_only)
  #   - rc!=0 with 1141 (no such grant — root@host absent)             → PASS
  #     (host carries no user-facing root at all; nothing to bypass)
  #   - rc!=0 otherwise (1044 access denied, connection failure, etc.) → FAIL
  #     (verifier could not observe; do not infer fence state)
  #
  # The kubeblocks.kb_post_dcs_fence_probe table is no longer required by
  # this verifier, but the bootstrap-time ensure_internal_local_admin path
  # in cmpd-replication-merged.yaml still creates it so legacy callers and
  # diagnostics that inspect it (e.g. case appendices) keep working.
  # alpha.105 v2 R1 fix (Helen TL review): a single `mariadb -e "stmt1;
  # stmt2; stmt3"` invocation short-circuits on the first error (default
  # client behavior) and reports a non-zero exit. If any of the per-host
  # SHOW GRANTS hits 1141 (no such grant), later host queries never run
  # and earlier host output is still attached to the same `out` capture.
  # A naïve `case rc!=0 in *1141* return 0` would then false-PASS even
  # when an earlier host already revealed a bypass-class grant. Switch to
  # per-host loop: one mariadb invocation per host, classify each
  # independently, fail the moment any host shows bypass, count 1141 as
  # "no account on that host", and only PASS when no host showed bypass
  # AND at least one host returned a usable grant list (or all hosts are
  # 1141 — host set is genuinely empty).
  local rc host_count=0 missing_count=0
  if [ -z "${MARIADB_CLIENT_BIN}" ] || [ ! -x "${MARIADB_CLIENT_BIN}" ]; then
    log_switchover_error "Switchover failed: post-DCS local-root write fence verification cannot run without MARIADB_CLIENT_BIN"
    return 1
  fi
  for host in '%' '127.0.0.1' 'localhost'; do
    host_count=$((host_count + 1))
    local out
    out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_INTERNAL_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h127.0.0.1 -N -s -e "SHOW GRANTS FOR 'root'@'${host}';" 2>&1)
    rc=$?
    if [ "${rc}" -ne 0 ]; then
      case "${out}" in
        *1141*)
          missing_count=$((missing_count + 1))
          log_switchover_info "Switchover post-DCS local-root write fence verification: 'root'@'${host}' absent (1141), skipping"
          continue
          ;;
      esac
      log_switchover_error "Switchover failed: post-DCS local-root write fence verification SHOW GRANTS FOR 'root'@'${host}' failed rc=${rc} out=${out}"
      return 1
    fi
    # Word-boundary match: avoid false hits on SUPER inside other words
    # and on tokens whose name happens to share a prefix with the bypass
    # set (SLAVE MONITOR / REPLICATION MASTER ADMIN / BINLOG MONITOR are
    # all NON-bypass grants present on the alpha.83 narrowed root and
    # must not trip this scan). `grep -E` keeps the regex compact and
    # the patterns explicit. "SUPER" is matched only when surrounded
    # by `[, ]` (privilege list separator) or sitting at start/end of
    # the line. ALL PRIVILEGES is matched as a defensive catch-all in
    # case the chart bootstrap revoke step never ran.
    if printf '%s\n' "${out}" | grep -qE "$(root_read_only_bypass_pattern_for_host "${host}")"; then
      log_switchover_error "Switchover failed: post-DCS local-root write fence not enforced; 'root'@'${host}' still holds a read_only-bypass privilege ($(root_read_only_bypass_label_for_host "${host}")). grants=${out}"
      return 1
    fi
  done
  if [ "${missing_count}" -eq "${host_count}" ]; then
    log_switchover_info "Switchover post-DCS local-root write fence verified via read-only privilege query: no user-facing root account present on any of @%/@127.0.0.1/@localhost (all hosts 1141)"
    return 0
  fi
  log_switchover_info "Switchover post-DCS local-root write fence verified via read-only privilege query: user-facing root carries no read_only-bypass privilege on any present host (checked=${host_count}, missing=${missing_count})"
  return 0
}

fence_current_primary_local_writes_after_dcs() {
  local current_name
  current_name=$(resolve_current_name)
  log_switchover_info "Switchover post-DCS guard: setting current primary ${current_name} read_only=ON before candidate can accept writes"
  local fence_attempt=1
  local fence_max=10
  local syncer_race_hold=3
  while [ "${fence_attempt}" -le "${fence_max}" ]; do
    set_local_read_only "ON" 2>/dev/null || true
    if local_read_only_is "1"; then
      log_switchover_info "Switchover post-DCS read_only=ON set at attempt=${fence_attempt}, holding ${syncer_race_hold}s for syncer race window"
      sleep "${syncer_race_hold}"
      if local_read_only_is "1"; then
        log_switchover_info "Switchover post-DCS read_only=ON stable after ${syncer_race_hold}s hold at attempt=${fence_attempt}"
        break
      fi
      log_switchover_info "Switchover post-DCS read_only reverted during hold (syncer race), re-setting (attempt=${fence_attempt}/${fence_max})"
    else
      log_switchover_info "Switchover post-DCS read_only=ON not yet confirmed, retrying (attempt=${fence_attempt}/${fence_max})"
    fi
    sleep 1
    fence_attempt=$((fence_attempt + 1))
  done
  if ! local_read_only_is "1"; then
    log_switchover_error "Switchover failed: current primary read_only=ON was not stable after ${fence_max} attempts"
    return 1
  fi
  # alpha.60 + alpha.124: synchronously revoke user-facing root admin bypass
  # privileges. READ_ONLY ADMIN / SUPER are disallowed everywhere; BINLOG ADMIN
  # is disallowed on non-local root hosts but allowed for local loopback/socket
  # root because chart-internal sql_log_bin=0 paths need it and it does not
  # bypass read_only by itself. Restoration of secondary follow-time grants
  # stays in roleProbe secondary path - this action does NOT re-grant read_only
  # bypass privileges.
  if ! revoke_user_facing_root_admin_privileges_for_secondary; then
    return 1
  fi
  if ! verify_post_dcs_local_root_write_fenced; then
    return 1
  fi
  log_switchover_info "Switchover post-DCS guard passed for current primary ${current_name}: read_only=1 + user-facing root admin bypass revoked + local INSERT fenced (1290)"
  return 0
}

syncerctl_switchover() {
  # alpha.61 v3 (Jack 02:23 review): syncerctl is wrapped by timeout(1) using
  # min(SYNCERCTL_PER_CALL_TIMEOUT_SECONDS, dcs_budget) when caller passes
  # ${3}. timeout(1) exit codes 124 (default SIGTERM after timeout) and 137
  # (KILL via --kill-after, defensive) and 125 (timeout's own error) are
  # mapped to a distinct sentinel `syncerctl_timeout` so closeout can tell
  # "wall-clock budget exhausted" from "syncerctl reported a real failure".
  # Without the wrapper (callers that don't pass dcs_budget — currently
  # untested call sites) the legacy naked path is preserved for backward
  # compatibility but emits the legacy `syncerctl exited with rc=` sentinel.
  local current_name="$1"
  local candidate_name="$2"
  local stage_budget="${3:-}"
  local output
  local rc
  local using_timeout=0

  # alpha.79 v2 (Helen TL autopilot 22:31 westonnnn `442a5d2e`): pass --force
  # so syncer overrides any leftover "previous switchover unfinished" DCS
  # record from a prior successful switchover. n1ad same-cluster repeat axis
  # (2026-05-14 ~14:54 UTC) exposed this: after the first GREEN switchover
  # cleared chart-side state and OpsRequest reached Succeed, syncer's DCS
  # record stayed in "unfinished" state. Repeat switchovers got
  # `Create switchover failed: there is another switchover
  # maria-5d-n1ad-mariadb-switchover unfinished`. Using --force on every
  # invocation is safe: first-time switchovers have no leftover record so
  # --force is a no-op; repeated switchovers proceed cleanly. This is a
  # syncer-layer cleanup gap (syncer should mark its own DCS record done
  # when the switchover protocol completes); --force is a chart-side
  # workaround until syncer side cleans up properly.
  if [ -n "${stage_budget}" ] && [ "${SWITCHOVER_HAS_TIMEOUT}" = "1" ]; then
    local wall="${SYNCERCTL_PER_CALL_TIMEOUT_SECONDS}"
    if [ "${stage_budget}" -lt "${wall}" ]; then wall="${stage_budget}"; fi
    if [ "${wall}" -lt 1 ]; then wall=1; fi
    using_timeout=1
    output=$(timeout "${wall}" "${SYNCERCTL_BIN}" --host "${SYNCERCTL_HOST}" --port "${SYNCERCTL_PORT}" \
      switchover --force --primary "${current_name}" --candidate "${candidate_name}" 2>&1)
    rc=$?
  else
    output=$("${SYNCERCTL_BIN}" --host "${SYNCERCTL_HOST}" --port "${SYNCERCTL_PORT}" \
      switchover --force --primary "${current_name}" --candidate "${candidate_name}" 2>&1)
    rc=$?
  fi

  if [ -n "${output}" ]; then
    log_switchover_info "Switchover syncerctl output: ${output}"
  else
    log_switchover_info "Switchover syncerctl output: <empty>"
  fi

  # timeout(1) wall-clock exhaustion → distinct sentinel.
  if [ "${using_timeout}" = "1" ]; then
    case "${rc}" in
      124|125|137)
        log_switchover_error "Switchover failed: reason=syncerctl_timeout stage=dcs stage_budget=${stage_budget}s rc=${rc}; fail-closed"
        return 1
        ;;
    esac
  fi

  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: syncerctl exited with rc=${rc}"
    return 1
  fi
  case "${output}" in
    *"switchover success"*) return 0 ;;
    *)
      log_switchover_error "Switchover failed: syncerctl did not report success"
      return 1
      ;;
  esac
}

candidate_is_primary() {
  local candidate_fqdn="$1"
  local read_only
  local slave_status

  if ! has_mariadb_client; then
    [ "$(query_syncer_role "${candidate_fqdn}")" = "primary" ]
    return $?
  fi

  read_only=$(query_value "${candidate_fqdn}" "SELECT @@global.read_only;")
  slave_status=$(query_slave_status "${candidate_fqdn}")

  [ "${read_only}" = "0" ] || return 1
  [ -z "${slave_status}" ] || return 1
  # alpha.62 v1 (Jack 04:08 DRIFT B fold-out): legacy candidate full-access
  # grants check removed. After alpha.60 v2 unfence + alpha.61 v3 roleProbe
  # primary fence, the candidate's user-facing root grants no longer match
  # the legacy `GRANT ALL PRIVILEGES` signature; the explicit-primary-grant
  # check now lives at the local-fence callsite (rollback verifier — see
  # remote_root_has_explicit_primary_grant). For candidate primary state, the remaining
  # 4 signals (read_only=0 + no slave_status + remote_root_primary_ready +
  # syncer role=primary) are sufficient. alpha.127 makes the root check
  # non-mutating: repeated switchover retries must not create orphan GTIDs on
  # a temporary candidate.
  remote_root_primary_ready "${candidate_fqdn}" "candidate-primary" || return 1
  syncer_role_is "${candidate_fqdn}" "primary"
}

slave_status_is_ready_for_candidate() {
  local slave_status="$1"
  local candidate_name="$2"
  local candidate_fqdn="$3"

  [ -n "${slave_status}" ] || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_IO_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Slave_SQL_Running: Yes" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_IO_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -q "Last_SQL_Errno: 0" || return 1
  printf "%s" "${slave_status}" | grep -F "Master_Host: ${candidate_fqdn}" >/dev/null 2>&1 ||
  printf "%s" "${slave_status}" | grep -F "Master_Host: ${candidate_name}" >/dev/null 2>&1
}

slave_status_has_kb_health_check_repairable_error() {
  local slave_status="$1"
  [ -n "${slave_status}" ] || return 1
  printf "%s" "${slave_status}" | grep -qE "Last_SQL_Errno: 1062|Last_Errno: 1062|Last_SQL_Errno: 1146|Last_Errno: 1146" || return 1
  printf "%s" "${slave_status}" | grep -q "kubeblocks.kb_health_check" || return 1
}

clear_local_kb_health_check_table() {
  local decision="$1"
  if run_local_maintenance_sql "
    SET SESSION sql_log_bin=0;
    CREATE DATABASE IF NOT EXISTS kubeblocks;
    CREATE TABLE IF NOT EXISTS kubeblocks.kb_health_check(type INT, check_ts BIGINT, PRIMARY KEY(type));
    DELETE FROM kubeblocks.kb_health_check;
    SET SESSION sql_log_bin=1;
  "; then
    log_switchover_info "Switchover old-primary follow repair: prepared local kubeblocks health check table (${decision})"
    return 0
  fi
  log_switchover_error "Switchover old-primary follow repair: failed to prepare local kubeblocks health check table (${decision})"
  return 1
}

repair_kb_health_check_replication_error() {
  local slave_status="$1"
  if ! slave_status_has_kb_health_check_repairable_error "${slave_status}"; then
    return 1
  fi
  log_switchover_info "Switchover old-primary follow repair: detected repairable kubeblocks health check replication error"
  run_local_sql_best_effort "STOP SLAVE SQL_THREAD;"
  if ! clear_local_kb_health_check_table "prepared-local-kb-health-check-after-switchover-replication-error"; then
    return 1
  fi
  run_local_sql_best_effort "START SLAVE SQL_THREAD;"
  return 0
}

current_follows_candidate() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local read_only
  local slave_status

  if ! has_mariadb_client; then
    [ "$(query_syncer_role "127.0.0.1")" = "secondary" ]
    return $?
  fi

  read_only=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  [ "${read_only}" = "1" ] || return 1
  syncer_role_is "127.0.0.1" "secondary" || return 1

  slave_status=$(query_slave_status "127.0.0.1")
  if slave_status_is_ready_for_candidate "${slave_status}" "${candidate_name}" "${candidate_fqdn}"; then
    return 0
  fi
  if repair_kb_health_check_replication_error "${slave_status}"; then
    slave_status=$(query_slave_status "127.0.0.1")
    slave_status_is_ready_for_candidate "${slave_status}" "${candidate_name}" "${candidate_fqdn}" && return 0
  fi
  return 1
}

switchover_final_state_already_reached() {
  local current_name="$1"
  local candidate_name="$2"
  local candidate_fqdn="$3"
  local read_only
  local slave_status

  # Duplicate lifecycle-action invocations can arrive after the first call has
  # already completed the DCS switchover. Accept that path only after observing
  # the desired database truth directly; absence of an error is not enough.
  if ! has_mariadb_client; then
    log_switchover_info "Switchover idempotent closeout skipped: mariadb client unavailable"
    return 1
  fi

  if ! candidate_is_primary "${candidate_fqdn}"; then
    log_switchover_info "Switchover idempotent closeout not satisfied: candidate ${candidate_name} is not positively observed as primary"
    return 1
  fi

  read_only=$(query_value "127.0.0.1" "SELECT @@global.read_only;")
  if [ "${read_only}" != "1" ]; then
    log_switchover_info "Switchover idempotent closeout not satisfied: current ${current_name} read_only=${read_only:-<empty>} expected=1"
    return 1
  fi

  if ! syncer_role_is "127.0.0.1" "secondary"; then
    log_switchover_info "Switchover idempotent closeout not satisfied: current ${current_name} syncer role is not secondary"
    return 1
  fi

  slave_status=$(query_slave_status "127.0.0.1")
  if ! slave_status_is_ready_for_candidate "${slave_status}" "${candidate_name}" "${candidate_fqdn}"; then
    log_switchover_info "Switchover idempotent closeout not satisfied: current ${current_name} is not positively following candidate ${candidate_name}"
    return 1
  fi

  log_switchover_info "Switchover idempotent success: desired final state already reached current=${current_name} candidate=${candidate_name}; candidate primary observed and current follows candidate"
  return 0
}

primary_service_routes_candidate() {
  local candidate_fqdn="$1"
  local candidate_server_id
  local service_server_id

  candidate_server_id=$(query_server_id "${candidate_fqdn}")
  [ -n "${candidate_server_id}" ] || return 1

  service_server_id=$(query_server_id "$(resolve_primary_service_fqdn)")
  [ "${service_server_id}" = "${candidate_server_id}" ]
}

log_primary_service_route_diagnostic() {
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local primary_service_fqdn
  local candidate_server_id
  local service_server_id
  local route_status="pending"
  local observation

  primary_service_fqdn=$(resolve_primary_service_fqdn)
  candidate_server_id=$(query_server_id "${candidate_fqdn}")
  service_server_id=$(query_server_id "${primary_service_fqdn}")
  if [ -n "${candidate_server_id}" ] && [ "${service_server_id}" = "${candidate_server_id}" ]; then
    route_status="matched"
  fi
  observation="candidate=${candidate_name} candidate_fqdn=${candidate_fqdn} primary_service=${primary_service_fqdn} expected_server_id=${candidate_server_id:-<empty-or-error>} service_server_id=${service_server_id:-<empty-or-error>} route_status=${route_status}"
  echo "Switchover service-route diagnostic: ${observation}"
  return 0
}

now_epoch() {
  # POSIX wall-clock seconds. Returns rc=2 (NOT 0 with empty output) on date
  # failure or non-numeric output so callers can distinguish "0 seconds since
  # action start" from "clock unavailable". rc=2 propagates as fail-closed.
  local ts
  ts=$(date +%s 2>/dev/null) || return 2
  case "${ts}" in
    ''|*[!0-9]*) return 2 ;;
  esac
  printf '%s' "${ts}"
}

initialize_action_clock() {
  # Called once at run_switchover entry. Captures the action start epoch and
  # asserts `timeout(1)` is present. Either failure is fatal BEFORE we touch
  # DCS so we never run with a silently broken clock or an unbounded external
  # call. v3 (Jack 02:23 review): `timeout` is now a hard dependency — when
  # absent we fail at action entry, NOT at the promote stage.
  local now
  now=$(now_epoch)
  if [ -z "${now}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable cause=date_failed; fail-closed"
    return 1
  fi
  action_started_epoch="${now}"
  if command -v timeout >/dev/null 2>&1; then
    SWITCHOVER_HAS_TIMEOUT=1
  else
    SWITCHOVER_HAS_TIMEOUT=0
    log_switchover_error "Switchover failed: reason=external_timeout_unavailable cause=command_v_timeout_failed; fail-closed (action_entry; DCS not touched)"
    return 1
  fi
  return 0
}

remaining_action_budget() {
  # Echo the integer remaining budget in seconds (may be 0 or negative).
  # Returns 2 on clock failure -- caller MUST treat as fail-closed, never as
  # "0 seconds remaining" silent fallback (Jack 02:00 review #1).
  local now
  now=$(now_epoch)
  if [ -z "${now}" ]; then
    printf '0'
    return 2
  fi
  case "${action_started_epoch}" in
    ''|*[!0-9]*) printf '0'; return 2 ;;
  esac
  local elapsed=$(( now - action_started_epoch ))
  local remaining=$(( SWITCHOVER_ACTION_DEADLINE_SECONDS - elapsed ))
  printf '%s' "${remaining}"
  return 0
}

action_elapsed_seconds() {
  # Best-effort elapsed seconds for log messages. Returns "?" on clock failure
  # so logs stay informative even when the deadline path itself failed closed.
  local now
  now=$(now_epoch)
  if [ -z "${now}" ] || [ -z "${action_started_epoch}" ]; then
    printf '?'
    return 0
  fi
  printf '%s' "$(( now - action_started_epoch ))"
}

stage_budget_or_exit() {
  # Compute min(stage_max, remaining_global). On clock failure or
  # remaining<=0, log fail-closed with reason=action_deadline_exhausted_<stage>
  # and return 1 so the caller exits before invoking the stage body. On
  # success, prints the chosen budget so the caller can capture it.
  local stage_name="$1"
  local stage_max="$2"
  local remaining
  remaining=$(remaining_action_budget)
  local rc=$?
  if [ "${rc}" -ne 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_${stage_name} cause=action_clock_unavailable elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed"
    return 1
  fi
  if [ "${remaining}" -le 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_${stage_name} elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed"
    return 1
  fi
  local budget="${stage_max}"
  if [ "${remaining}" -lt "${budget}" ]; then
    budget="${remaining}"
  fi
  printf '%s' "${budget}"
  return 0
}

extract_syncerctl_role() {
  # Read syncerctl getrole output and return the role token if present.
  # Looks for a line that, after trimming, equals exactly "primary" or
  # "secondary". Echoes empty string if no match. POSIX-safe: no $'\n'
  # case patterns, no bashism (Jack 02:00 review #1).
  local out="$1"
  printf '%s\n' "${out}" | awk '
    { sub(/^[[:space:]]+/, ""); sub(/[[:space:]]+$/, "");
      if ($0 == "primary" || $0 == "secondary") { print $0; exit } }
  '
}

run_syncerctl_getrole_with_timeout() {
  # Wrap syncerctl getrole with `timeout <wall>` where wall=min(per_call,
  # stage_budget). Caller MUST verify SWITCHOVER_HAS_TIMEOUT=1 before invoking
  # this (we don't silently fall back to an unbounded call).
  local fqdn="$1"
  local stage_budget="$2"
  local wall="${SYNCERCTL_PER_CALL_TIMEOUT_SECONDS}"
  if [ "${stage_budget}" -lt "${wall}" ]; then
    wall="${stage_budget}"
  fi
  if [ "${wall}" -lt 1 ]; then
    wall=1
  fi
  timeout "${wall}" "${SYNCERCTL_BIN}" --host "${fqdn}" --port "${SYNCERCTL_PORT}" getrole 2>&1
}

wait_candidate_sql_reachable_before_dcs() {
  # Syncer performs a single candidate read-check inside `switchover`. r59
  # observed a post-restart window where the runner's prior SQL check passed
  # but syncer's immediate pre-DCS TCP connect to candidate:3306 got connection
  # refused. This bounded pre-DCS gate keeps that transient inside the action's
  # global deadline and fails before touching DCS if the candidate stays closed.
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local stage_budget="$3"
  local start
  local now
  local elapsed=0
  local attempt=1
  local last_rc=0
  local connect_timeout
  local poll_seconds="${SWITCHOVER_CANDIDATE_CONNECT_READY_POLL_SECONDS}"

  case "${stage_budget}" in
    ''|*[!0-9]*) stage_budget=0 ;;
  esac
  if [ "${stage_budget}" -le 0 ]; then
    log_switchover_error "Switchover failed: reason=candidate_sql_not_reachable_before_dcs_in_budget candidate=${candidate_name} stage_budget=${stage_budget}s attempts=0 last_rc=not_attempted; fail-closed (DCS not touched)"
    return 1
  fi
  case "${poll_seconds}" in
    ''|*[!0-9]*) poll_seconds=1 ;;
  esac

  start=$(now_epoch)
  if [ -z "${start}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_connect; fail-closed"
    return 1
  fi

  while [ "${elapsed}" -lt "${stage_budget}" ]; do
    connect_timeout="${SWITCHOVER_CANDIDATE_CONNECT_READY_CONNECT_TIMEOUT_SECONDS}"
    case "${connect_timeout}" in
      ''|*[!0-9]*) connect_timeout=1 ;;
    esac
    if [ "${connect_timeout}" -lt 1 ]; then
      connect_timeout=1
    fi
    if [ $(( stage_budget - elapsed )) -lt "${connect_timeout}" ]; then
      connect_timeout=$(( stage_budget - elapsed ))
      if [ "${connect_timeout}" -lt 1 ]; then
        connect_timeout=1
      fi
    fi

    if run_sql_with_connect_timeout "${candidate_fqdn}" "${connect_timeout}" "SELECT 1;"; then
      log_switchover_info "Switchover candidate SQL reachable before DCS: candidate=${candidate_name} fqdn=${candidate_fqdn} attempt=${attempt} elapsed=${elapsed}s connect_timeout=${connect_timeout}s"
      return 0
    fi
    last_rc=$?
    log_switchover_info "Switchover candidate SQL not reachable before DCS: candidate=${candidate_name} fqdn=${candidate_fqdn} attempt=${attempt} elapsed=${elapsed}s connect_timeout=${connect_timeout}s rc=${last_rc}; retrying"

    sleep "${poll_seconds}"
    attempt=$((attempt + 1))
    now=$(now_epoch)
    if [ -z "${now}" ]; then
      log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_connect; fail-closed"
      return 1
    fi
    elapsed=$(( now - start ))
  done

  log_switchover_error "Switchover failed: reason=candidate_sql_not_reachable_before_dcs_in_budget candidate=${candidate_name} stage_budget=${stage_budget}s attempts=$((attempt - 1)) last_rc=${last_rc}; fail-closed (DCS not touched)"
  return 1
}

wait_candidate_promoted_via_syncerctl() {
  # alpha.61 (Jack 01:40 review): before testing candidate writability, the
  # action MUST observe that DCS has actually promoted the candidate (i.e.,
  # syncerctl getrole on the candidate FQDN returns "primary"). alpha.59
  # accidentally hid the missing-promotion case because user-facing root held
  # READ_ONLY ADMIN and could INSERT through `read_only=1`. After alpha.60's
  # revoke, root cannot bypass; we must wait for actual promotion.
  #
  # Sentinels per Jack class 4: role_unknown (empty/unrecognized output),
  # role_query_failed (rc!=0 + stderr captured), role_not_primary (e.g. still
  # secondary), candidate_fqdn_not_found (DNS / pod missing). Stage budget is
  # clamped by the caller-provided remaining deadline so we never overshoot
  # the global 55s action ceiling.
  #
  # alpha.61 v2 (Jack 02:00 review): replaced bash-only $SECONDS with POSIX
  # now_epoch(); replaced $'\n' case patterns with extract_syncerctl_role()
  # awk parser; required SWITCHOVER_HAS_TIMEOUT=1 so syncerctl can never block
  # longer than min(per_call, stage_budget) seconds.
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local stage_deadline="${3:-${CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS}}"

  if [ -z "${candidate_fqdn}" ]; then
    log_switchover_error "Switchover failed: reason=candidate_fqdn_not_found candidate=${candidate_name}; fail-closed"
    return 1
  fi
  if [ "${SWITCHOVER_HAS_TIMEOUT}" != "1" ]; then
    log_switchover_error "Switchover failed: reason=external_timeout_unavailable stage=candidate_promoted; fail-closed"
    return 1
  fi
  local stage_started_epoch
  stage_started_epoch=$(now_epoch)
  if [ -z "${stage_started_epoch}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_promoted; fail-closed"
    return 1
  fi

  local attempt=0 last_role="" last_rc="" last_stderr=""
  local stage_elapsed=0
  while :; do
    local now
    now=$(now_epoch)
    if [ -z "${now}" ]; then
      log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_promoted; fail-closed"
      return 1
    fi
    stage_elapsed=$(( now - stage_started_epoch ))
    if [ "${stage_elapsed}" -ge "${stage_deadline}" ]; then
      break
    fi
    attempt=$((attempt + 1))
    local per_call_remaining=$(( stage_deadline - stage_elapsed ))
    last_stderr=$(run_syncerctl_getrole_with_timeout "${candidate_fqdn}" "${per_call_remaining}")
    last_rc=$?
    last_role=$(extract_syncerctl_role "${last_stderr}")
    if [ "${last_rc}" -eq 0 ] && [ "${last_role}" = "primary" ]; then
      log_switchover_info "Switchover candidate promoted via DCS observed: candidate=${candidate_name} attempt=${attempt} role=primary rc=0 elapsed=${stage_elapsed}s"
      return 0
    fi
    if [ "${last_rc}" -ne 0 ]; then
      log_switchover_info "Switchover candidate promotion poll attempt=${attempt} reason=role_query_failed rc=${last_rc} stderr=${last_stderr}"
    elif [ -z "${last_role}" ]; then
      log_switchover_info "Switchover candidate promotion poll attempt=${attempt} reason=role_unknown rc=0 stderr=${last_stderr}"
    else
      log_switchover_info "Switchover candidate promotion poll attempt=${attempt} reason=role_not_primary role=${last_role} rc=0"
    fi
    sleep "${SWITCHOVER_POLL_SECONDS}"
  done
  log_switchover_error "Switchover failed: reason=candidate_not_promoted_via_dcs_in_budget candidate=${candidate_name} attempts=${attempt} stage_budget=${stage_deadline}s last_role=${last_role:-<empty>} last_rc=${last_rc} last_stderr=${last_stderr}; fail-closed"
  return 1
}

wait_candidate_remote_root_primary_ready() {
  # alpha.59: bounded synchronous probe of the candidate's primary readiness.
  # After alpha.61's wait_candidate_promoted_via_syncerctl precondition, this probe
  # should converge in 1-2s under healthy conditions; the budget is kept
  # because read_only/account state may lag slightly even after syncerctl
  # role flip. SQL stderr/stdout is now captured per attempt (Jack 01:40 review)
  # so a non-rc=0 outcome can be attributed (probe_sql_stderr_<errno> /
  # probe_connection_failed) instead of opaque rc=1.
  #
  # alpha.61 v2 (Jack 02:00 review): replaced bash-only $SECONDS with POSIX
  # now_epoch(); SQL probe inherits MARIADB_CONNECT_TIMEOUT_SECONDS and the
  # stage budget bound through this polling loop. Clock failure mid-loop is
  # fail-closed (no silent fallback).
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local stage_deadline="${3:-${CANDIDATE_REMOTE_ROOT_PRIMARY_READY_WAIT_SECONDS}}"

  local stage_started_epoch
  stage_started_epoch=$(now_epoch)
  if [ -z "${stage_started_epoch}" ]; then
    log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_primary_ready; fail-closed"
    return 1
  fi

  local attempt=0 last_out="" last_rc=""
  local stage_elapsed=0
  while :; do
    local now
    now=$(now_epoch)
    if [ -z "${now}" ]; then
      log_switchover_error "Switchover failed: reason=action_clock_unavailable stage=candidate_primary_ready; fail-closed"
      return 1
    fi
    stage_elapsed=$(( now - stage_started_epoch ))
    if [ "${stage_elapsed}" -ge "${stage_deadline}" ]; then
      break
    fi
    attempt=$((attempt + 1))
    if remote_root_primary_ready "${candidate_fqdn}" "candidate-remote-root-primary-ready"; then
      log_switchover_info "Switchover candidate remote root primary-readiness probe converged for ${candidate_name} attempt=${attempt} elapsed=${stage_elapsed}s"
      return 0
    fi
    # Capture stdout+stderr explicitly for attribution. This is intentionally
    # non-mutating; do not add DDL/DML here.
    last_out=$("${MARIADB_CLIENT_BIN}" "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
      --connect-timeout="${MARIADB_CONNECT_TIMEOUT_SECONDS}" \
      -P3306 -h"${candidate_fqdn}" -N -s -e "
        SELECT @@global.read_only;
      " 2>&1)
    last_rc=$?
    log_switchover_info "Switchover candidate remote root primary-readiness probe attempt=${attempt} rc=${last_rc} observation=${last_out}"
    sleep "${SWITCHOVER_POLL_SECONDS}"
  done

  log_switchover_error "Switchover failed: reason=candidate_remote_root_primary_not_ready_in_budget candidate=${candidate_name} attempts=${attempt} stage_budget=${stage_deadline}s last_rc=${last_rc} last_observation=${last_out}; fail-closed"
  return 1
}

run_switchover() {
  # alpha.61 v2 contract (Jack 02:00 review): POSIX wall clock + staged
  # deadline enforcement. Each stage entry checks the remaining global budget
  # FIRST via stage_budget_or_exit; if exhausted (or wall clock fails), emits
  # action_deadline_exhausted_<stage> and returns 1 BEFORE invoking the stage
  # body. Stage budget = min(stage_max, remaining_global_budget).
  #
  # Stages (each with its own action_deadline_exhausted_<stage> sentinel):
  #   1. prepare       - prepare_current_primary_for_switchover
  #   2. candidate_connect - bounded candidate SQL reachability before syncer
  #   3. dcs           - syncerctl_switchover (DCS record)
  #   4. fence         - fence_current_primary_local_writes_after_dcs
  #                      (revoke admin-bypass + verify_post_dcs_local_root_write_fenced)
  #   5. promote       - wait_candidate_promoted_via_syncerctl
  #   6. ready         - wait_candidate_remote_root_primary_ready
  #
  # External tools that can block:
  #   - syncerctl getrole: wrapped with timeout(1) (initialize_action_clock
  #     verifies command existence; absence of `timeout` fails the action).
  #   - mariadb client SQL probes: bounded by --connect-timeout=
  #     ${MARIADB_CONNECT_TIMEOUT_SECONDS} on connect, and by stage budget
  #     on the polling loop (so cumulative wall time per stage is bounded).
  #
  # Post-DCS convergence (Primary Service endpoint route, old-primary follow,
  # secondary fence, kb_health_check 1062 repair) is delegated to roleProbe
  # + KB endpoint controller; runner side has its own bounded post-OpsRequest
  # gate.
  local candidate_name="$1"
  local candidate_fqdn="$2"
  local current_name
  current_name=$(resolve_current_name)

  if [ -z "${current_name}" ]; then
    echo "Switchover failed: current primary name is empty" >&2
    return 1
  fi
  if [ -z "${candidate_name}" ]; then
    echo "Switchover failed: candidate name is empty" >&2
    return 1
  fi

  if ! initialize_action_clock; then
    return 1
  fi
  log_switchover_info "Switchover action global deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; per-stage budgets clamped by remaining wall-clock time. has_timeout=${SWITCHOVER_HAS_TIMEOUT}"

  # Stage 1: prepare
  local prepare_budget
  prepare_budget=$(stage_budget_or_exit "prepare" "${SWITCHOVER_PREPARE_STAGE_BUDGET_SECONDS}") || return 1
  log_switchover_info "Switchover stage prepare budget=${prepare_budget}s remaining_before=$(remaining_action_budget)s"
  if ! prepare_current_primary_for_switchover; then
    return 1
  fi
  # alpha.61 v3 (Jack 02:23 review): post-stage overrun check. The stage
  # body's inner SQL helpers do not yet enforce the stage budget per-call
  # (caveat: alpha.61 v3 caps scope to keep alpha.60 revoke main path
  # untouched). If the stage body wall-clock exceeds the budget, fail closed
  # with a distinct `_overrun` sentinel BEFORE entering the next stage so
  # downstream stages don't run with zero remaining time.
  local remaining_after_prepare
  remaining_after_prepare=$(remaining_action_budget)
  if [ $? -ne 0 ] || [ "${remaining_after_prepare}" -le 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_prepare_overrun elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed (stage body exceeded budget)"
    return 1
  fi

  # Stage 2: candidate SQL reachability before syncer precheck touches DCS.
  local candidate_connect_budget
  candidate_connect_budget=$(stage_budget_or_exit "candidate_connect" "${SWITCHOVER_CANDIDATE_CONNECT_READY_WAIT_SECONDS}") || return 1
  log_switchover_info "Switchover stage candidate_connect budget=${candidate_connect_budget}s remaining_before=$(remaining_action_budget)s candidate=${candidate_name}"
  if ! wait_candidate_sql_reachable_before_dcs "${candidate_name}" "${candidate_fqdn}" "${candidate_connect_budget}"; then
    rollback_current_primary_switchover_guard || true
    return 1
  fi

  # Stage 3: DCS switchover
  local dcs_budget
  dcs_budget=$(stage_budget_or_exit "dcs" "${SWITCHOVER_DCS_STAGE_BUDGET_SECONDS}") || return 1
  log_switchover_info "Switchover stage dcs budget=${dcs_budget}s remaining_before=$(remaining_action_budget)s primary=${current_name} candidate=${candidate_name}"
  log_switchover_info "Switchover: creating syncer DCS switchover primary=${current_name} candidate=${candidate_name}"
  if ! syncerctl_switchover "${current_name}" "${candidate_name}" "${dcs_budget}"; then
    if switchover_final_state_already_reached "${current_name}" "${candidate_name}" "${candidate_fqdn}"; then
      return 0
    fi
    rollback_current_primary_switchover_guard || true
    log_switchover_error "Switchover failed: syncerctl could not create DCS switchover"
    return 1
  fi
  # Defensive overrun guard mirrors prepare (DCS is bounded by the timeout(1)
  # wrapper but the rollback guard above is best-effort and could itself
  # consume time).
  local remaining_after_dcs
  remaining_after_dcs=$(remaining_action_budget)
  if [ $? -ne 0 ] || [ "${remaining_after_dcs}" -le 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_dcs_overrun elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed (stage body exceeded budget)"
    return 1
  fi

  # Stage 4: fence current primary local writes (revoke + verify)
  local fence_budget
  fence_budget=$(stage_budget_or_exit "fence" "${SWITCHOVER_FENCE_STAGE_BUDGET_SECONDS}") || return 1
  log_switchover_info "Switchover stage fence budget=${fence_budget}s remaining_before=$(remaining_action_budget)s"
  if ! fence_current_primary_local_writes_after_dcs; then
    log_switchover_error "Switchover failed: current primary local write fence did not close after DCS switchover"
    return 1
  fi
  local remaining_after_fence
  remaining_after_fence=$(remaining_action_budget)
  if [ $? -ne 0 ] || [ "${remaining_after_fence}" -le 0 ]; then
    log_switchover_error "Switchover failed: reason=action_deadline_exhausted_fence_overrun elapsed=$(action_elapsed_seconds)s deadline=${SWITCHOVER_ACTION_DEADLINE_SECONDS}s; fail-closed (stage body exceeded budget)"
    return 1
  fi

  # Stage 5: candidate promoted via syncerctl
  local promoted_budget
  promoted_budget=$(stage_budget_or_exit "promote" "${CANDIDATE_PROMOTED_VIA_SYNCERCTL_WAIT_SECONDS}") || return 1
  log_switchover_info "Switchover stage candidate_promoted budget=${promoted_budget}s remaining_before=$(remaining_action_budget)s"
  if ! wait_candidate_promoted_via_syncerctl "${candidate_name}" "${candidate_fqdn}" "${promoted_budget}"; then
    return 1
  fi

  # Stage 6: candidate remote root primary-readiness probe
  local ready_budget
  ready_budget=$(stage_budget_or_exit "ready" "${CANDIDATE_REMOTE_ROOT_PRIMARY_READY_WAIT_SECONDS}") || return 1
  log_switchover_info "Switchover stage candidate_primary_ready budget=${ready_budget}s remaining_before=$(remaining_action_budget)s"
  if ! wait_candidate_remote_root_primary_ready "${candidate_name}" "${candidate_fqdn}" "${ready_budget}"; then
    return 1
  fi

  log_switchover_info "Switchover action returned: DCS recorded, current primary fenced, candidate promoted via DCS, candidate root primary-readiness observed without mutating probe. Total elapsed=$(action_elapsed_seconds)s of ${SWITCHOVER_ACTION_DEADLINE_SECONDS}s deadline. Post-DCS convergence delegated to roleProbe + KB endpoint controller."
  return 0
}

main() {
  if [ "${KB_SWITCHOVER_ROLE}" != "primary" ]; then
    echo "Not the primary, nothing to do."
    return 0
  fi
  setup_mariadb_client_bin || return 1

  local candidate_name
  local candidate_fqdn
  candidate_name=$(resolve_candidate_name)
  candidate_fqdn=$(resolve_candidate_fqdn)
  # alpha.80 v1 (Helen): the alpha.76 unconditional clear_switchover_fence_
  # active_marker call has been removed. alpha.79 v1 minimalist deleted the
  # marker writer in prepare, so no marker exists to clear. Pure dead-code
  # cleanup, no runtime behavior change.
  run_switchover "${candidate_name}" "${candidate_fqdn}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

set -e
main
