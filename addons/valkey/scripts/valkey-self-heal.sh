#!/bin/bash
# valkey-self-heal.sh
#
# Long-running self-heal daemon, sourced + spawned by valkey-start.sh
# (`self_heal_maintenance_loop &` before `exec valkey-server`). Lives in
# the valkey container. After valkey-start.sh's exec, this daemon is
# reparented to valkey-server (PID 1). valkey-server does not actively reap
# unrelated children, but a single long-lived daemon does NOT accumulate —
# it stays as a single process throughout the pod lifetime.
#
# Why an entrypoint daemon (not a probe-fork or kbagent custom probe):
#   1) We need self-heal to run periodically without consuming roleProbe
#      latency budget (cmpd roleProbe.timeoutSeconds is small).
#   2) Self-heal triggered from the kbagent-driven probe (the original
#      design) leaks zombies in the kbagent container — kbagent's PID 1
#      is a Go binary that does not reap unrelated orphans. See
#      docs/addon-probe-script-fork-and-zombie-guide.md
#      (Pattern A: explicit `&` fork; Pattern B: implicit pipeline orphan
#      after kbagent SIGKILL on probe timeout).
#   3) Forking once at entrypoint (this design) is the same idiom used by
#      clickhouse `sync_user_xml`, mariadb-galera wsrep monitor, and
#      postgresql `restart_for_pending_restart_flag`. All proven.
#
# What it does (per CHECK_INTERVAL_SECONDS, after INITIAL_DELAY_SECONDS):
#   1) Cascade-topology repair — if this pod is `role:slave`, query the
#      configured master; if that master is itself a slave (cascade
#      topology Sentinel does NOT auto-correct), issue REPLICAOF directly
#      to the real master at the head of the chain. Three guards
#      (PR #2615 semantics):
#        - skip-stale-role: re-read local role just before issuing REPLICAOF
#        - skip-self-target: cascade chain may fold back to ourselves
#        - remote-master-unreachable: timeout-bounded INFO; skip on timeout
#   2) Full-sync stall recovery (Bug 5 fix) — if this pod is `role:slave`
#      and `master_sync_in_progress=1` AND `master_sync_read_bytes=0` for
#      longer than STALL_THRESHOLD_SECONDS, send SIGTERM to PID 1 to trigger
#      a container restart. This handles the diskless-sync race that leaves
#      a slave permanently stuck in full-sync after rapid A→B→C failover.
#
# Stderr is captured by the kubelet from the valkey container's main
# process (after exec) and surfaced via `kubectl logs <pod> -c valkey`.

CHECK_INTERVAL_SECONDS="${CHECK_INTERVAL_SECONDS:-${CASCADE_CHECK_INTERVAL_SECONDS:-30}}"
CASCADE_REMOTE_TIMEOUT_SECONDS="${CASCADE_REMOTE_TIMEOUT_SECONDS:-2}"
INITIAL_DELAY_SECONDS="${INITIAL_DELAY_SECONDS:-${CASCADE_INITIAL_DELAY_SECONDS:-30}}"
STALL_THRESHOLD_SECONDS="${STALL_THRESHOLD_SECONDS:-60}"
STALL_MARKER_FILE="${STALL_MARKER_FILE:-/tmp/valkey_sync_stall_since}"
# ut_mode is shared between this daemon and shellspec; keep the default
# false so tests that don't set ut_mode still see real behavior.
SELF_HEAL_UT_MODE="${ut_mode:-false}"

cascade_build_local_cli_cmd() {
  local port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
  local cmd="valkey-cli --no-auth-warning -h 127.0.0.1 -p ${port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  fi
  echo "${cmd}"
}

cascade_build_remote_cli_cmd() {
  local host="$1"
  local port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
  local cmd="valkey-cli --no-auth-warning -h ${host} -p ${port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    cmd="${cmd} ${VALKEY_CLI_TLS_ARGS}"
  fi
  echo "${cmd}"
}

cascade_info_replication_with_timeout() {
  local cmd="$1"
  if command -v timeout >/dev/null 2>&1 && [ "${CASCADE_REMOTE_TIMEOUT_SECONDS}" != "0" ]; then
    timeout "${CASCADE_REMOTE_TIMEOUT_SECONDS}" ${cmd} info replication 2>/dev/null
    return $?
  fi
  ${cmd} info replication 2>/dev/null
}

cascade_extract_replication_field() {
  local repl_info="$1" field="$2"
  echo "${repl_info}" | grep "^${field}:" | tr -d '\r\n' | cut -d: -f2
}

# cascade_is_self_host — same semantics as the original is_self_host that
# lived in check-role.sh (PR #2615 self-target guard).  Adjusted to also
# accept POD_FQDN as the FQDN env (valkey container env in cmpd.yaml uses
# POD_FQDN; KB_POD_FQDN is the roleProbe action env), with KB_POD_FQDN as
# fallback so the function behaves identically wherever it is sourced from.
cascade_is_self_host() {
  local host="${1%.}"
  local current_pod="${CURRENT_POD_NAME:-}"
  local current_fqdn="${POD_FQDN:-${KB_POD_FQDN:-}}"
  current_fqdn="${current_fqdn%.}"

  case "${host}" in
    "127.0.0.1"|"localhost"|"::1")
      return 0
      ;;
  esac

  if [ -n "${current_pod}" ]; then
    [ "${host}" = "${current_pod}" ] && return 0
    contains "${host}" "${current_pod}." && return 0
  fi
  [ -n "${current_fqdn}" ] && [ "${host}" = "${current_fqdn}" ] && return 0

  if command -v getent >/dev/null 2>&1 && [ -n "${current_fqdn}" ]; then
    local host_ips current_ips ip
    host_ips=$(getent hosts "${host}" 2>/dev/null | awk '{print $1}' | sort -u) || true
    current_ips=$(getent hosts "${current_fqdn}" 2>/dev/null | awk '{print $1}' | sort -u) || true
    for ip in ${host_ips}; do
      echo "${current_ips}" | grep -qx "${ip}" && return 0
    done
  fi

  return 1
}

# cascade_check_one_round — a single inspection-and-repair iteration.
# Mirrors the original check_cascade_topology body from check-role.sh,
# preserving PR #2615 guards (remote-master-unreachable + skip-stale-role
# + skip-self-target).
cascade_check_one_round() {
  local local_port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
  local cli_cmd
  cli_cmd=$(cascade_build_local_cli_cmd)

  local repl_info
  repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0

  local role_line
  role_line=$(cascade_extract_replication_field "${repl_info}" "role")
  [ "${role_line}" != "slave" ] && return 0

  local master_host
  master_host=$(cascade_extract_replication_field "${repl_info}" "master_host")
  is_empty "${master_host}" && return 0

  local remote_cli
  remote_cli=$(cascade_build_remote_cli_cmd "${master_host}")

  local master_repl_info master_role
  master_repl_info=$(cascade_info_replication_with_timeout "${remote_cli}") || {
    echo "INFO: skip cascade repair (remote-master-unreachable): cannot query ${master_host} within ${CASCADE_REMOTE_TIMEOUT_SECONDS}s." >&2
    return 0
  }
  master_role=$(cascade_extract_replication_field "${master_repl_info}" "role")
  [ "${master_role}" != "slave" ] && return 0

  local real_master_host real_master_port
  real_master_host=$(cascade_extract_replication_field "${master_repl_info}" "master_host")
  real_master_port=$(cascade_extract_replication_field "${master_repl_info}" "master_port")
  is_empty "${real_master_host}" && return 0

  # PR #2615 Guard 1 — stale-role race: between the time we read role:slave
  # at the start of this round and now, Sentinel may have promoted this pod.
  # Issuing REPLICAOF on a fresh master would demote it. Re-read local role.
  local current_repl_info current_role
  current_repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0
  current_role=$(cascade_extract_replication_field "${current_repl_info}" "role")
  if [ "${current_role}" != "slave" ]; then
    echo "INFO: skip cascade repair (skip-stale-role): local role is '${current_role:-unknown}', not slave." >&2
    return 0
  fi

  # PR #2615 Guard 2 — self-target: chain may fold back (A → B → A).
  if cascade_is_self_host "${real_master_host}"; then
    echo "WARNING: skip cascade repair (skip-self-target): target ${real_master_host}:${real_master_port:-${local_port}} resolves to current pod ${CURRENT_POD_NAME:-unknown}." >&2
    return 0
  fi

  echo "WARNING: cascading topology — our master ${master_host} is a slave of ${real_master_host}. Issuing REPLICAOF to reconnect directly to real master." >&2
  ${cli_cmd} REPLICAOF "${real_master_host}" "${real_master_port:-${local_port}}" 2>/dev/null || true
}

# stall_check_one_round — Bug 5 (full-sync stall) detector.
# Called only when local role == slave. Detects:
#   master_sync_in_progress=1 AND master_sync_read_bytes=0 for > STALL_THRESHOLD_SECONDS
# Action: trigger container restart via SIGTERM to PID 1 (valkey-server).
#
# Implementation note (Pattern B avoidance — preserved from the original
# probe-path implementation in check-role.sh):
#   The original probe-path version parsed INFO output with two 4-stage
#   pipelines (`echo|grep|tr|cut`). When the kbagent-driven roleProbe
#   SIGKILLs the script for exceeding timeoutSeconds, each pipeline's
#   children get reparented to kbagent (PID 1, Go binary, non-reaper) and
#   accumulate as zombies (~9 observed per upgrade window in R2).
#
#   Even though this function now lives in the entrypoint daemon (PID 1 =
#   valkey-server, single long-lived process, no SIGKILL exposure), we
#   keep the bash-builtin parse for defense in depth: zero forks per
#   iteration means stall detection never spawns subprocesses regardless
#   of where it is called from.
stall_check_one_round() {
  local cli_cmd repl_info sync_in_progress read_bytes line role_line
  cli_cmd=$(cascade_build_local_cli_cmd)
  repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0

  # Single-process parse: bash builtins only, no pipeline / cmd-substitution
  # children that could leak under any future SIGKILL exposure.
  role_line=""
  sync_in_progress=""
  read_bytes=""
  while IFS= read -r line; do
    line="${line%$'\r'}"
    case "${line}" in
      role:*)                    role_line="${line#role:}" ;;
      master_sync_in_progress:*) sync_in_progress="${line#master_sync_in_progress:}" ;;
      master_sync_read_bytes:*)  read_bytes="${line#master_sync_read_bytes:}" ;;
    esac
  done <<<"${repl_info}"

  # Stall detection only meaningful for slaves mid-sync.
  [ "${role_line}" != "slave" ] && return 0

  if [ "${sync_in_progress}" = "1" ] && [ "${read_bytes}" = "0" ]; then
    if [ ! -f "${STALL_MARKER_FILE}" ]; then
      date +%s > "${STALL_MARKER_FILE}"
      echo "WARNING: full-sync stall detected (master_sync_read_bytes=0), started tracking." >&2
      return 0
    fi
    local stall_since elapsed
    stall_since=$(cat "${STALL_MARKER_FILE}" 2>/dev/null) || return 0
    elapsed=$(( $(date +%s) - stall_since ))
    if [ "${elapsed}" -ge "${STALL_THRESHOLD_SECONDS}" ]; then
      echo "ERROR: full-sync stall persisted for ${elapsed}s (threshold ${STALL_THRESHOLD_SECONDS}s) — restarting server." >&2
      rm -f "${STALL_MARKER_FILE}"
      stall_restart_server_for_recovery
    else
      echo "WARNING: full-sync stall ongoing for ${elapsed}s / ${STALL_THRESHOLD_SECONDS}s threshold." >&2
    fi
  else
    if [ -f "${STALL_MARKER_FILE}" ]; then
      echo "INFO: full-sync stall resolved, removing marker." >&2
      rm -f "${STALL_MARKER_FILE}"
    fi
  fi
}

stall_restart_server_for_recovery() {
  if [ "${SELF_HEAL_UT_MODE}" = "true" ]; then
    echo "ut_mode: would send SIGTERM to PID 1 (valkey-server) to restart container" >&2
    return 0
  fi
  kill -SIGTERM 1
}

# dual_master_confirm_demote — bounded poll after issuing REPLICAOF, with
# the strict success criterion required by Bob2 review angle #2 (sub-detail
# 2): both role transitions to slave AND master_host points to the
# quorum-elected master. Anything else is reported as a partial / stuck
# state for the next round to retry.
DUAL_MASTER_CONFIRM_TIMEOUT_SECONDS="${DUAL_MASTER_CONFIRM_TIMEOUT_SECONDS:-10}"
DUAL_MASTER_CONFIRM_POLL_INTERVAL_SECONDS="${DUAL_MASTER_CONFIRM_POLL_INTERVAL_SECONDS:-1}"

dual_master_confirm_demote() {
  local cli_cmd="$1"
  local expected_master_host="$2"
  local deadline=$((SECONDS + DUAL_MASTER_CONFIRM_TIMEOUT_SECONDS))
  while [ "${SECONDS}" -lt "${deadline}" ]; do
    sleep "${DUAL_MASTER_CONFIRM_POLL_INTERVAL_SECONDS}"
    local repl_info post_role post_master_host
    repl_info=$(${cli_cmd} info replication 2>/dev/null) || continue
    post_role=$(cascade_extract_replication_field "${repl_info}" "role")
    post_master_host=$(cascade_extract_replication_field "${repl_info}" "master_host")
    if [ "${post_role}" = "slave" ] && [ -n "${post_master_host}" ]; then
      if [ "${post_master_host}" = "${expected_master_host}" ] \
         || _dm_hosts_resolve_same "${post_master_host}" "${expected_master_host}"; then
        return 0
      fi
    fi
  done
  return 1
}

# _dm_hosts_resolve_same — best-effort same-host comparison for the
# bounded-confirmation step. Sentinel may report the master as a pod FQDN
# while INFO replication's master_host may be an IP (or vice-versa).  We
# DNS-resolve both sides and check for any common IP.  Returns 0 on match,
# 1 otherwise.  Failure to resolve = no match (passive / safe default).
_dm_hosts_resolve_same() {
  local a="${1%.}" b="${2%.}"
  [ -z "${a}" ] || [ -z "${b}" ] && return 1
  [ "${a}" = "${b}" ] && return 0
  if command -v getent >/dev/null 2>&1; then
    local a_ips b_ips ip
    a_ips=$(getent hosts "${a}" 2>/dev/null | awk '{print $1}' | sort -u) || true
    b_ips=$(getent hosts "${b}" 2>/dev/null | awk '{print $1}' | sort -u) || true
    for ip in ${a_ips}; do
      echo "${b_ips}" | grep -qx "${ip}" && return 0
    done
  fi
  return 1
}

# dual_master_check_one_round — detect rogue-master state and demote.
#
# Evidence anchor: KB-10196 — when KB controller's isExclusive enforcement
# clears the K8s role label on a duplicate-primary pod, sentinel correctly
# elects a single master via quorum, but Sentinel protocol only reconfigures
# slaves; it does NOT issue REPLICAOF to demote a self-claimed master that
# was not the elected one.  This function fills that gap from the addon
# side: each pod periodically asks sentinel-quorum "who is master?" and,
# if it sees itself running as master while quorum says someone else is
# master, issues REPLICAOF against itself to demote.
#
# Guards (Bob2 review angles + reviewer feedback):
#   - skip-no-sentinel: SENTINEL_COMPONENT_NAME / SENTINEL_POD_FQDN_LIST
#     unset → no truth source available → return without action.
#   - skip-not-master: local INFO replication says role != master → nothing
#     to demote.
#   - skip-no-helper: query_sentinel_quorum_for_master is sourced from
#     valkey-start.sh in production but absent under shellspec when the
#     spec sources only valkey-self-heal.sh.  Use declare -F guard so the
#     daemon stays passive in test environments without a real sentinel.
#   - quorum-clear gate: only act when query_sentinel_quorum_for_master
#     returns a non-empty FQDN (it already implements >= floor(N/2)+1
#     majority); empty return = "uncertain" → return without action
#     (passive-when-uncertain).
#   - skip-self-target: if quorum master resolves to self, sentinel agrees
#     we are the legitimate master → nothing to do.
#   - skip-stale-role: re-read local role just before issuing REPLICAOF
#     (between initial read and decision, sentinel may have re-elected us).
#   - bounded confirmation: see dual_master_confirm_demote above.
dual_master_check_one_round() {
  is_empty "${SENTINEL_COMPONENT_NAME}" && return 0
  is_empty "${SENTINEL_POD_FQDN_LIST}" && return 0

  local local_port="${KB_SERVICE_PORT:-${SERVICE_PORT:-6379}}"
  local cli_cmd
  cli_cmd=$(cascade_build_local_cli_cmd)

  local repl_info role_line
  repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0
  role_line=$(cascade_extract_replication_field "${repl_info}" "role")
  [ "${role_line}" != "master" ] && return 0

  if ! declare -F query_sentinel_quorum_for_master >/dev/null 2>&1; then
    # Helper not sourced (e.g. shellspec single-file mode).  Stay passive.
    return 0
  fi

  local quorum_master_fqdn
  quorum_master_fqdn=$(query_sentinel_quorum_for_master 2>/dev/null) || true
  if is_empty "${quorum_master_fqdn}"; then
    echo "INFO: skip dual-master demote (quorum-unclear): query_sentinel_quorum_for_master returned empty (no majority consensus yet)." >&2
    return 0
  fi

  if cascade_is_self_host "${quorum_master_fqdn}"; then
    # Sentinel-quorum agrees we are the legitimate master.
    return 0
  fi

  # Data-plane verification: confirm the quorum-elected master actually
  # reports role:master in its engine state.  Sentinel quorum may lag or
  # point to a pod that was itself just demoted / restarted.  Issuing
  # REPLICAOF to a non-master would create a cascade slave chain (the
  # exact class of failure this daemon is designed to repair).  If the
  # remote is unreachable or not yet master, skip this round and retry.
  local remote_cli remote_info remote_role
  remote_cli=$(cascade_build_remote_cli_cmd "${quorum_master_fqdn}")
  remote_info=$(cascade_info_replication_with_timeout "${remote_cli}") || {
    echo "INFO: skip dual-master demote (skip-quorum-target-unreachable): cannot query ${quorum_master_fqdn} within ${CASCADE_REMOTE_TIMEOUT_SECONDS}s." >&2
    return 0
  }
  remote_role=$(cascade_extract_replication_field "${remote_info}" "role")
  if [ "${remote_role}" != "master" ]; then
    echo "INFO: skip dual-master demote (skip-quorum-target-not-master): ${quorum_master_fqdn} reports role='${remote_role:-unknown}', not yet master." >&2
    return 0
  fi

  # Skip-stale-role: re-read just before REPLICAOF.
  local current_repl_info current_role
  current_repl_info=$(${cli_cmd} info replication 2>/dev/null) || return 0
  current_role=$(cascade_extract_replication_field "${current_repl_info}" "role")
  if [ "${current_role}" != "master" ]; then
    echo "INFO: skip dual-master demote (skip-stale-role): local role is '${current_role:-unknown}', no longer master." >&2
    return 0
  fi

  echo "WARNING: rogue master detected — sentinel-quorum reports real master is '${quorum_master_fqdn}'; demoting self via REPLICAOF." >&2
  ${cli_cmd} REPLICAOF "${quorum_master_fqdn}" "${local_port}" 2>/dev/null || true

  if dual_master_confirm_demote "${cli_cmd}" "${quorum_master_fqdn}"; then
    echo "INFO: dual-master demote confirmed: now role:slave attached to '${quorum_master_fqdn}'." >&2
    return 0
  fi

  echo "WARNING: dual-master demote NOT confirmed within ${DUAL_MASTER_CONFIRM_TIMEOUT_SECONDS}s — local role may still be 'master' or master_host may not match. Will retry next round." >&2
  return 0
}

self_heal_maintenance_loop() {
  echo "INFO: self-heal daemon starting (interval=${CHECK_INTERVAL_SECONDS}s, remote-timeout=${CASCADE_REMOTE_TIMEOUT_SECONDS}s, stall-threshold=${STALL_THRESHOLD_SECONDS}s)" >&2
  # Initial delay lets valkey-server come up before we start probing.
  sleep "${INITIAL_DELAY_SECONDS}"
  while true; do
    cascade_check_one_round     || true
    stall_check_one_round       || true
    dual_master_check_one_round || true
    sleep "${CHECK_INTERVAL_SECONDS}"
  done
}
