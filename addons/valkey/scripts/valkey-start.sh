#!/bin/bash
# valkey-start.sh — renders valkey.conf and starts valkey-server.
#
# Learning note:
#   The startup script is the "glue" between KubeBlocks' variable injection
#   and the actual database process.  KubeBlocks delivers all vars[] values
#   as environment variables before this script runs.  The script's job is to
#   translate those env vars into the database-specific configuration file and
#   then exec the server.
#
#   Key design choices here:
#   1. We keep the config template read-only (mounted ConfigMap) and write
#      all dynamic settings to /etc/valkey/valkey.conf (emptyDir).
#   2. We use `include /etc/conf/valkey.conf` in the runtime conf so the
#      template's static defaults are honoured without copying them.
#   3. `exec valkey-server` replaces the shell process — PID 1 in the
#      container is the database, which is what Kubernetes expects for
#      proper signal handling.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

CONF_TEMPLATE="/etc/conf/valkey.conf"
CONF_RUNTIME="/etc/valkey/valkey.conf"
ACL_FILE="/data/users.acl"
ACL_FILE_BAK="/data/users.acl.bak"
service_port="${SERVICE_PORT:-6379}"

load_common_library() {
  # shellcheck disable=SC1091
  source /scripts/common.sh
}

# Build the writable runtime conf by including the template and appending
# dynamic settings that depend on environment variables.
build_valkey_conf() {
  # Step 1: include the static template
  echo "include ${CONF_TEMPLATE}" > "${CONF_RUNTIME}"

  # Step 2: port (plain or TLS)
  if [ "${TLS_ENABLED}" = "true" ]; then
    echo "tls-port ${service_port}" >> "${CONF_RUNTIME}"
  else
    echo "port ${service_port}" >> "${CONF_RUNTIME}"
  fi

  # Step 3: announce IP/port for replication topology.
  # When using NodePort or LoadBalancer, replicas must announce the
  # external address so peers outside the cluster can connect.
  build_announce_addr

  # Step 4: replicaof — determine whether this pod is primary or secondary
  build_replicaof_config

  # Step 5: ACL / password
  rebuild_acl_file
  build_acl_entries
  echo "aclfile ${ACL_FILE}" >> "${CONF_RUNTIME}"
}

build_announce_addr() {
  # Prefer per-pod NodePort, then LoadBalancer, then FQDN.
  local announce_host=""
  local announce_port=""

  # NodePort path
  if ! is_empty "${VALKEY_ADVERTISED_PORT}"; then
    local pod_ordinal
    pod_ordinal=$(extract_obj_ordinal "${CURRENT_POD_NAME}")
    # VALKEY_ADVERTISED_PORT format: "podSvc1:nodePort1,podSvc2:nodePort2,..."
    for entry in $(echo "${VALKEY_ADVERTISED_PORT}" | tr ',' '\n'); do
      local svc_name port
      svc_name="${entry%%:*}"
      port="${entry##*:}"
      if [ "$(extract_obj_ordinal "${svc_name}")" = "${pod_ordinal}" ]; then
        announce_port="${port}"
        announce_host="${CURRENT_POD_HOST_IP}"
        break
      fi
    done
  fi

  # LoadBalancer path (overrides NodePort host if available)
  if is_empty "${announce_host}" && ! is_empty "${VALKEY_LB_ADVERTISED_PORT}"; then
    local pod_ordinal
    pod_ordinal=$(extract_obj_ordinal "${CURRENT_POD_NAME}")
    for entry in $(echo "${VALKEY_LB_ADVERTISED_PORT}" | tr ',' '\n'); do
      local svc_name port
      svc_name="${entry%%:*}"
      port="${entry##*:}"
      if [ "$(extract_obj_ordinal "${svc_name}")" = "${pod_ordinal}" ]; then
        announce_port="${service_port}"
        # Extract LB host from VALKEY_LB_ADVERTISED_HOST (format: "svc1:host1,svc2:host2")
        for lb_entry in $(echo "${VALKEY_LB_ADVERTISED_HOST}" | tr ',' '\n'); do
          if [ "${lb_entry%%:*}" = "${svc_name}" ]; then
            announce_host="${lb_entry##*:}"
            break
          fi
        done
        break
      fi
    done
  fi

  # Fall back to pod FQDN
  if is_empty "${announce_host}"; then
    local pod_fqdn
    pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "${VALKEY_POD_FQDN_LIST}" "${CURRENT_POD_NAME}")
    if is_empty "${pod_fqdn}"; then
      echo "ERROR: cannot determine FQDN for ${CURRENT_POD_NAME}" >&2
      exit 1
    fi
    announce_host="${pod_fqdn}"
    announce_port="${service_port}"
  fi

  if ! is_empty "${announce_host}"; then
    echo "replica-announce-ip ${announce_host}" >> "${CONF_RUNTIME}"
    echo "replica-announce-port ${announce_port}" >> "${CONF_RUNTIME}"
  fi
}

build_replicaof_config() {
  local primary_fqdn=""
  local primary_port="${service_port}"

  if ! is_empty "${SENTINEL_COMPONENT_NAME}" && ! is_empty "${SENTINEL_POD_FQDN_LIST}"; then
    # ── Path A: sentinel-managed cluster ────────────────────────────────
    # Sentinel is the authoritative source of truth for who is master.
    #
    # Step A-1: query ALL sentinels and require quorum consensus (majority
    # agreement on the same master FQDN) before trusting the result.
    # This prevents split-brain caused by scale-in or failover-timeout overlap,
    # where different sentinels transiently hold different master epochs.
    #
    # Retry up to 6 times (5s apart ≈ 54s total including verify timeouts)
    # to cover the sentinel failover convergence window before falling back
    # to direct pod scan.  Must complete within the liveness probe kill
    # window (initialDelay 30s + failureThreshold×period = 90s) so the
    # heuristic election fallback (step A-3) has time to run.
    local attempt
    for attempt in $(seq 1 6); do
      primary_fqdn=$(query_sentinel_quorum_for_master) || true
      if ! is_empty "${primary_fqdn}"; then
        # Verify the quorum-elected pod actually reports role=master right now.
        # Even with quorum agreement, sentinel can converge to a different master
        # between when different pods query — the earlier quorum answer may point
        # to a pod that has already been demoted to slave.  Following a slave as
        # master creates circular replication (A→B, B→A → both become masters).
        local actual_role
        actual_role=$(verify_pod_role "${primary_fqdn}") || true
        if [ "${actual_role}" = "master" ]; then
          echo "INFO: sentinel quorum + role verified: ${primary_fqdn}:${primary_port}" >&2
          break
        fi
        echo "INFO: quorum elected ${primary_fqdn} but role='${actual_role:-<unreachable>}' — retrying in 5s." >&2
        primary_fqdn=""
      else
        echo "INFO: sentinel quorum not ready (attempt ${attempt}/6) — retrying in 5s." >&2
      fi
      if [ "${attempt}" -lt 6 ]; then
        sleep_when_ut_mode_false 5
      fi
    done

    if is_empty "${primary_fqdn}"; then
      # Step A-2: sentinel hasn't registered the master yet (e.g. simultaneous
      # restart, background discovery loop still running).  Scan the data pods
      # directly — whichever one is already up and reports role:master is the
      # ground truth.  Retry up to 3 times (3s apart) to tolerate transient
      # connection failures under resource contention (e.g. many pods restarting
      # simultaneously on EKS can cause brief TCP timeouts to surviving pods).
      echo "INFO: sentinel exhausted — scanning data pods for running master." >&2
      local scan_attempt
      for scan_attempt in 1 2 3; do
        primary_fqdn=$(scan_pods_for_master) || true
        if ! is_empty "${primary_fqdn}"; then
          echo "INFO: found running master via pod scan (attempt ${scan_attempt}): ${primary_fqdn}" >&2
          break
        fi
        if [ "${scan_attempt}" -lt 3 ]; then
          echo "INFO: pod scan empty (attempt ${scan_attempt}/3) — retrying in 3s." >&2
          sleep 3
        fi
      done
      if ! is_empty "${primary_fqdn}"; then
        : # already logged above
      else
        # Step A-3: no peer is a master yet. Fresh component bootstrap and
        # clean full-component restart both need one pod to seed the topology
        # by lexicographic order. Existing data alone is not unsafe: Stop/Start
        # preserves PVC data while every data pod is down. The unsafe signal is
        # observing an already-running slave while Sentinel cannot prove the
        # master; guessing then can create a second master after restart/restore.
        local known_slave_fqdn
        known_slave_fqdn=$(find_known_slave_pod) || true
        if ! is_empty "${known_slave_fqdn}"; then
          echo "ERROR: Sentinel topology has no trusted master but ${known_slave_fqdn} reports role:slave — refusing lexicographic primary guess." >&2
          return 1
        fi
        if ! is_fresh_bootstrap_data_dir; then
          echo "INFO: Sentinel topology has no trusted master and ${DATA_DIR:-/data} contains existing data, but no running peer role was observed — treating as full-cluster restart." >&2
        fi
        # Elect the lowest-ordinal pod as the bootstrap primary, then verify it
        # is actually reporting role:master.
        # During rolling restarts the lexicographic pod may itself be a slave
        # (sentinel already failed over to a different pod); connecting to it
        # would create a cascading topology that sentinel will not auto-correct.
        echo "INFO: no running master found — electing bootstrap primary by lexicographic order." >&2
        local heuristic_fqdn
        heuristic_fqdn=$(elect_lexicographic_primary)
        local heuristic_role
        heuristic_role=$(verify_pod_role "${heuristic_fqdn}") || true
        if [ "${heuristic_role}" = "master" ] || is_empty "${heuristic_role}"; then
          # Confirmed master, or pod unreachable (fresh cluster bootstrap).
          primary_fqdn="${heuristic_fqdn}"
        else
          # Heuristic pod is a slave — follow its replication chain to find the
          # real master and avoid creating a cascading sub-slave topology.
          echo "INFO: heuristic pod ${heuristic_fqdn} is '${heuristic_role}' — finding real master." >&2
          local chained
          chained=$(follow_slave_to_master "${heuristic_fqdn}") || true
          if ! is_empty "${chained}"; then
            echo "INFO: real master via replication chain: ${chained}" >&2
            primary_fqdn="${chained}"
          else
            # Last resort: 3 extra quorum retries (10s apart).
            local retry
            for retry in 1 2 3; do
              sleep_when_ut_mode_false 10
              primary_fqdn=$(query_sentinel_quorum_for_master) || true
              if ! is_empty "${primary_fqdn}"; then
                echo "INFO: sentinel quorum found master on retry ${retry}: ${primary_fqdn}" >&2
                break
              fi
            done
            # Fall back to heuristic if all else fails (sentinel may be starting).
            is_empty "${primary_fqdn}" && primary_fqdn="${heuristic_fqdn}"
          fi
        fi
      fi
    fi
  else
    # ── Path B: no sentinel (standalone or fresh cluster) ───────────────
    echo "INFO: no sentinel configured — electing primary by lexicographic order." >&2
    primary_fqdn=$(elect_lexicographic_primary)
  fi

  if is_empty "${primary_fqdn}"; then
    echo "ERROR: could not determine primary FQDN — aborting." >&2
    exit 1
  fi

  # Always write masterauth so that if sentinel later demotes this pod via
  # REPLICAOF, it can authenticate to the new master without a restart.
  # (masterauth on a primary is harmless — only used when connecting upstream.)
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    echo "masteruser ${VALKEY_DEFAULT_USER:-default}" >> "${CONF_RUNTIME}"
    unset_xtrace_when_ut_mode_false
    echo "masterauth ${VALKEY_DEFAULT_PASSWORD}" >> "${CONF_RUNTIME}"
    set_xtrace_when_ut_mode_false
  fi

  # If this pod is the elected primary, no replicaof directive needed.
  if contains "${primary_fqdn}" "${CURRENT_POD_NAME}."; then
    echo "INFO: this pod is the primary — no replicaof directive needed." >&2
    return
  fi

  echo "replicaof ${primary_fqdn} ${primary_port}" >> "${CONF_RUNTIME}"
}

is_fresh_bootstrap_data_dir() {
  local dir="${DATA_DIR:-/data}"
  [ ! -e "${dir}/dump.rdb" ] || return 1
  [ ! -e "${dir}/appendonly.aof" ] || return 1
  [ ! -d "${dir}/appendonlydir" ] || return 1
  [ ! -e "${dir}/nodes.conf" ] || return 1
  return 0
}

# query_sentinel_quorum_for_master — query ALL sentinel pods and return the
# master FQDN only when a strict majority (>= floor(N/2)+1) agree on the same
# answer.  Returns empty string (exit 0) if no quorum consensus exists yet.
#
# This prevents split-brain during sentinel FAILOVER convergence windows:
# if scale-in deletes the master and sentinel is mid-FAILOVER, different
# sentinels may hold different epoch/master values.  Requiring quorum ensures
# we only follow a master that sentinel has durably elected.
query_sentinel_quorum_for_master() {
  local sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  local master_name="${VALKEY_COMPONENT_NAME}"

  # shellcheck disable=SC2206
  local sentinel_cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${sentinel_port}")
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    sentinel_cli_base+=(-a "${SENTINEL_PASSWORD}")
  fi

  IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
  local total="${#sentinel_fqdns[@]}"
  local quorum=$(( total / 2 + 1 ))

  # Collect each sentinel's answer as a list of "fqdn count" pairs using
  # parallel arrays (bash 3 compatible; pods run bash 4 on Linux but keep safe).
  local vote_keys=() vote_vals=()

  for s_fqdn in "${sentinel_fqdns[@]}"; do
    local response master_addr
    response=$(timeout 3 "${sentinel_cli_base[@]}" -h "${s_fqdn}" \
                 SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null) || continue
    master_addr=$(echo "${response}" | head -n1 | tr -d '\r\n')
    is_empty "${master_addr}" && continue
    [ "${master_addr}" = "(nil)" ] && continue

    # Resolve master_addr → FQDN from our known pod list.
    local resolved=""
    IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
    for pod_fqdn in "${pod_fqdns[@]}"; do
      local pod_ip
      pod_ip=$(getent hosts "${pod_fqdn}" 2>/dev/null | awk '{print $1}' | head -n1) || true
      if [ "${master_addr}" = "${pod_ip}" ] || [ "${master_addr}" = "${pod_fqdn}" ] || \
         contains "${pod_fqdn}" "${master_addr}."; then
        resolved="${pod_fqdn}"
        break
      fi
    done

    if is_empty "${resolved}"; then
      echo "WARNING: sentinel ${s_fqdn} returned master '${master_addr}' — no matching FQDN." >&2
      continue
    fi

    # Accumulate vote for this FQDN.
    local found=0
    local i
    for i in "${!vote_keys[@]}"; do
      if [ "${vote_keys[$i]}" = "${resolved}" ]; then
        vote_vals[$i]=$(( vote_vals[$i] + 1 ))
        found=1
        break
      fi
    done
    if [ "${found}" -eq 0 ]; then
      vote_keys+=("${resolved}")
      vote_vals+=(1)
    fi
  done

  # Find the candidate with the highest vote count.
  local winner="" winner_votes=0
  for i in "${!vote_keys[@]}"; do
    if [ "${vote_vals[$i]}" -gt "${winner_votes}" ]; then
      winner="${vote_keys[$i]}"
      winner_votes="${vote_vals[$i]}"
    fi
  done

  if [ "${winner_votes}" -ge "${quorum}" ]; then
    echo "${winner}"
    return 0
  fi

  if [ "${winner_votes}" -gt 0 ]; then
    echo "INFO: sentinel quorum not reached (best=${winner_votes}/${total}, need=${quorum})." >&2
  fi
  # No consensus — caller will retry or fall back to pod scan.
  return 0
}

# scan_pods_for_master — query every known data pod except ourselves and return
# the FQDN of whichever one reports role:master.
#
# This is the bridge between "sentinel is still initialising" and "fresh cluster
# with no master anywhere".  A non-empty result means an existing master is
# already running; empty means we need to bootstrap one via lexicographic order.
#
# We skip ourselves because valkey-server hasn't started yet and won't respond.
scan_pods_for_master() {
  # shellcheck disable=SC2206
  local cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${service_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_base+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi

  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for pod_fqdn in "${pod_fqdns[@]}"; do
    contains "${pod_fqdn}" "${CURRENT_POD_NAME}." && continue
    local role
    role=$(timeout 3 "${cli_base[@]}" -h "${pod_fqdn}" info replication 2>/dev/null \
      | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
    if [ "${role}" = "master" ]; then
      echo "${pod_fqdn}"
      return 0
    fi
  done
  return 0
}

find_known_slave_pod() {
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for pod_fqdn in "${pod_fqdns[@]}"; do
    contains "${pod_fqdn}" "${CURRENT_POD_NAME}." && continue
    local role
    role=$(verify_pod_role "${pod_fqdn}") || true
    if [ "${role}" = "slave" ]; then
      echo "${pod_fqdn}"
      return 0
    fi
  done
  return 0
}

# elect_lexicographic_primary — return the FQDN of the lowest-ordinal pod.
# Used only when no master is reachable (fresh cluster bootstrap or standalone).
elect_lexicographic_primary() {
  local primary_pod
  primary_pod=$(min_lexicographical_order_pod "${VALKEY_POD_NAME_LIST}")
  local fqdn
  fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "${VALKEY_POD_FQDN_LIST}" "${primary_pod}")
  if is_empty "${fqdn}"; then
    echo "ERROR: cannot resolve FQDN for lexicographic primary ${primary_pod}" >&2
    exit 1
  fi
  echo "${fqdn}"
}

# verify_pod_role — return the replication role ("master", "slave", or "") of a remote pod.
verify_pod_role() {
  local fqdn="$1"
  # shellcheck disable=SC2206
  local cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${service_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_base+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  local role
  role=$(timeout 3 "${cli_base[@]}" -h "${fqdn}" info replication 2>/dev/null \
    | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
  echo "${role}"
}

# follow_slave_to_master — given a slave FQDN, return the FQDN of the pod it
# replicates from.  Returns empty if the chain cannot be resolved to a known pod.
follow_slave_to_master() {
  local slave_fqdn="$1"
  # shellcheck disable=SC2206
  local cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${service_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_base+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  local master_host
  master_host=$("${cli_base[@]}" -h "${slave_fqdn}" info replication 2>/dev/null \
    | grep "^master_host:" | tr -d '\r\n' | cut -d: -f2) || true
  is_empty "${master_host}" && return 0
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for pod_fqdn in "${pod_fqdns[@]}"; do
    local pod_ip
    pod_ip=$(getent hosts "${pod_fqdn}" 2>/dev/null | awk '{print $1}' | head -n1) || true
    if [ "${master_host}" = "${pod_ip}" ] || [ "${master_host}" = "${pod_fqdn}" ] || \
       contains "${pod_fqdn}" "${master_host}."; then
      echo "${pod_fqdn}"
      return 0
    fi
  done
  return 0
}

rebuild_acl_file() {
  if [ -f "${ACL_FILE}" ]; then
    # Remove lines managed by us so we can rewrite them cleanly on restart.
    sed "/^user default /d" "${ACL_FILE}" > "${ACL_FILE_BAK}" \
      && mv "${ACL_FILE_BAK}" "${ACL_FILE}"
  else
    touch "${ACL_FILE}"
  fi
}

build_acl_entries() {
  unset_xtrace_when_ut_mode_false
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    local password_sha256
    password_sha256=$(echo -n "${VALKEY_DEFAULT_PASSWORD}" | sha256sum | cut -d' ' -f1)
    echo "user default on #${password_sha256} ~* &* +@all" >> "${ACL_FILE}"
    echo "protected-mode yes" >> "${CONF_RUNTIME}"
  else
    echo "user default on nopass ~* &* +@all" >> "${ACL_FILE}"
    echo "protected-mode no" >> "${CONF_RUNTIME}"
  fi
  set_xtrace_when_ut_mode_false
}

start_valkey_server() {
  echo "Starting: valkey-server ${CONF_RUNTIME}"
  exec valkey-server "${CONF_RUNTIME}"
}

start_self_heal_daemon() {
  # Spawn the self-heal daemon as a long-lived background process.
  # After `exec valkey-server`, this daemon is reparented to valkey-server
  # (PID 1).  valkey-server does not actively reap unrelated children, but
  # this is a single long-lived process — it does NOT accumulate.  Same
  # idiom as clickhouse `sync_user_xml`, mariadb-galera wsrep monitor, and
  # postgresql `restart_for_pending_restart_flag`.
  #
  # The daemon performs both cascade-topology repair and full-sync stall
  # recovery (Bug 5) per iteration. See addons/valkey/scripts/valkey-self-heal.sh
  # for rationale.
  # shellcheck source=/dev/null
  source /scripts/valkey-self-heal.sh
  self_heal_maintenance_loop &
  echo "Started self-heal daemon PID=$!"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library
build_valkey_conf
start_self_heal_daemon
start_valkey_server
