#!/bin/bash
# valkey-cascade-self-heal.sh
#
# Long-running cascade self-heal daemon, sourced + spawned by
# valkey-start.sh (`cascade_maintenance_loop &` before `exec valkey-server`).
# Lives in the valkey container.  After valkey-start.sh's exec, this daemon
# is reparented to valkey-server (PID 1).  valkey-server does not actively
# reap unrelated children, but a single long-lived daemon does NOT
# accumulate — it stays as a single process throughout the pod lifetime.
#
# Why an entrypoint daemon (not a probe-fork or kbagent custom probe):
#   1) We need cascade self-healing periodically without blocking roleProbe
#      latency budget (cmpd roleProbe.timeoutSeconds is small).
#   2) Forking from the kbagent-driven probe (the previous design) leaks
#      zombies in the kbagent container — kbagent's PID 1 is a Go binary
#      that does not reap unrelated orphans.  See
#      docs/addon-probe-script-fork-and-zombie-guide.md (Pattern A).
#   3) Forking once at entrypoint (this design) is the same idiom used by
#      clickhouse `sync_user_xml`, mariadb-galera wsrep monitor, and
#      postgresql `restart_for_pending_restart_flag`.  All proven in
#      production.
#
# What it does:
#   Every CASCADE_CHECK_INTERVAL_SECONDS, if this pod's local INFO
#   replication reports `role:slave`, query the configured master.  If that
#   master is itself a slave (cascading topology that Sentinel does not
#   auto-correct), issue REPLICAOF directly to the real master at the head
#   of the chain.  Three guards (PR #2615 semantics, kept here):
#   - skip-stale-role: re-read local role just before issuing REPLICAOF
#   - skip-self-target: cascade chain may fold back to ourselves
#   - remote-master-unreachable: timeout-bounded INFO; skip if master times out
#
# Stderr is captured by the kubelet from the valkey container's main
# process (after exec) and surfaced via `kubectl logs <pod> -c valkey`.

CASCADE_CHECK_INTERVAL_SECONDS="${CASCADE_CHECK_INTERVAL_SECONDS:-30}"
CASCADE_REMOTE_TIMEOUT_SECONDS="${CASCADE_REMOTE_TIMEOUT_SECONDS:-2}"
CASCADE_INITIAL_DELAY_SECONDS="${CASCADE_INITIAL_DELAY_SECONDS:-30}"

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

cascade_maintenance_loop() {
  echo "INFO: cascade maintenance daemon starting (interval=${CASCADE_CHECK_INTERVAL_SECONDS}s, remote-timeout=${CASCADE_REMOTE_TIMEOUT_SECONDS}s)" >&2
  # Initial delay lets valkey-server come up before we start probing.
  sleep "${CASCADE_INITIAL_DELAY_SECONDS}"
  while true; do
    cascade_check_one_round || true
    sleep "${CASCADE_CHECK_INTERVAL_SECONDS}"
  done
}
