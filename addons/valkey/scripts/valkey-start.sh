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
    # to direct pod scan. The pod remains NotReady until startup establishes
    # a safe topology and execs valkey-server.
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
        if ! primary_fqdn=$(scan_pods_for_master); then
          echo "ERROR: data pod scan found an ambiguous master view — refusing startup." >&2
          return 1
        fi
        if ! is_empty "${primary_fqdn}"; then
          echo "INFO: found running master via pod scan (attempt ${scan_attempt}): ${primary_fqdn}" >&2
          break
        fi
        if [ "${scan_attempt}" -lt 3 ]; then
          echo "INFO: pod scan empty (attempt ${scan_attempt}/3) — retrying in 3s." >&2
          sleep_when_ut_mode_false 3
        fi
      done
      if ! is_empty "${primary_fqdn}"; then
        : # already logged above
      else
        # Step A-3: no peer is a master yet. Only a fresh empty component may
        # seed topology by lexicographic order. Existing data cannot distinguish
        # a full restart from a partition, so it must wait for Sentinel or one
        # unambiguous running peer to provide authority.
        if ! is_fresh_bootstrap_data_dir; then
          echo "ERROR: Sentinel topology has no trusted master and ${DATA_DIR:-/data} contains existing data — refusing to guess whether this is a full restart or a network partition." >&2
          return 1
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
          # Confirmed master, or pod unreachable. When this pod is the fresh
          # lowest-ordinal bootstrap candidate, peers may already have started
          # as replicas of it under podManagementPolicy=Parallel. Accept that
          # narrow view only when every configured peer is reachable as a
          # replica and points back here.
          if is_empty "${heuristic_role}" && contains "${heuristic_fqdn}" "${CURRENT_POD_NAME}."; then
            if ! validate_parallel_bootstrap_replica_view "${heuristic_fqdn}"; then
              return 1
            fi
          fi
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
            if is_empty "${primary_fqdn}"; then
              echo "ERROR: heuristic pod ${heuristic_fqdn} is a replica but neither its upstream nor Sentinel can prove a current master." >&2
              return 1
            fi
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
  local unique_sentinel_fqdns=()
  local candidate known
  case ",${SENTINEL_POD_FQDN_LIST}," in
    *",,"*) return 0 ;;
  esac
  for candidate in "${sentinel_fqdns[@]}"; do
    [ -n "${candidate}" ] || return 0
    for known in "${unique_sentinel_fqdns[@]}"; do
      [ "${known}" != "${candidate}" ] || return 0
    done
    unique_sentinel_fqdns+=("${candidate}")
  done
  sentinel_fqdns=("${unique_sentinel_fqdns[@]}")
  local total="${#sentinel_fqdns[@]}"
  [ "${total}" -gt 0 ] || return 0
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
# the FQDN only when exactly one pod reports role:master.
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
  local masters=()
  for pod_fqdn in "${pod_fqdns[@]}"; do
    contains "${pod_fqdn}" "${CURRENT_POD_NAME}." && continue
    local role
    role=$(timeout 3 "${cli_base[@]}" -h "${pod_fqdn}" info replication 2>/dev/null \
      | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
    if [ "${role}" = "master" ]; then
      masters+=("${pod_fqdn}")
    fi
  done
  if [ "${#masters[@]}" -gt 1 ]; then
    echo "ERROR: multiple data pods report role:master: ${masters[*]}" >&2
    return 1
  fi
  if [ "${#masters[@]}" -eq 1 ]; then
    echo "${masters[0]}"
  fi
  return 0
}

get_replica_master_host() {
  local replica_fqdn="$1"
  # shellcheck disable=SC2206
  local cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${service_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_base+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi

  local master_host
  master_host=$(timeout 3 "${cli_base[@]}" -h "${replica_fqdn}" info replication 2>/dev/null \
    | grep "^master_host:" | tr -d '\r\n' | cut -d: -f2) || true
  echo "${master_host}"
}

get_replica_keyspace_info() {
  local replica_fqdn="$1"
  # shellcheck disable=SC2206
  local cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${service_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_base+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi

  timeout 3 "${cli_base[@]}" -h "${replica_fqdn}" info keyspace 2>/dev/null
}

get_replica_function_list() {
  local replica_fqdn="$1"
  # shellcheck disable=SC2206
  local cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${service_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cli_base+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi

  timeout 3 "${cli_base[@]}" -h "${replica_fqdn}" FUNCTION LIST 2>/dev/null
}

# A replica that already points at an unreachable fresh bootstrap candidate
# cannot have synchronized from that candidate. Its loaded keyspace and
# persisted Function libraries therefore prove whether it still carries data
# from an older topology.
validate_replica_keyspace_empty() {
  local replica_fqdn="$1"
  local keyspace_info
  if ! keyspace_info=$(get_replica_keyspace_info "${replica_fqdn}"); then
    echo "ERROR: replica ${replica_fqdn} keyspace evidence is unreadable — refusing bootstrap." >&2
    return 1
  fi

  local line db_name metrics keys
  local header_count=0
  local seen_dbs=()
  local seen_db
  while IFS= read -r line; do
    line="${line//$'\r'/}"
    case "${line}" in
      "")
        continue
        ;;
      "# Keyspace")
        header_count=$(( header_count + 1 ))
        [ "${header_count}" -eq 1 ] || {
          echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
          return 1
        }
        ;;
      db[0-9]*:keys=*)
        [ "${header_count}" -eq 1 ] || {
          echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
          return 1
        }
        db_name="${line%%:*}"
        metrics="${line#*:}"
        keys="${metrics%%,*}"
        keys="${keys#keys=}"
        case "${db_name#db}" in
          ""|*[!0-9]*)
            echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
            return 1
            ;;
        esac
        case "${keys}" in
          ""|*[!0-9]*)
            echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
            return 1
            ;;
        esac
        for seen_db in "${seen_dbs[@]}"; do
          [ "${seen_db}" != "${db_name}" ] || {
            echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
            return 1
          }
        done
        seen_dbs+=("${db_name}")
        if [ -n "${keys//0/}" ]; then
          echo "ERROR: replica ${replica_fqdn} retains ${keys} key(s) in ${db_name} — refusing bootstrap." >&2
          return 1
        fi
        ;;
      *)
        echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
        return 1
        ;;
    esac
  done <<< "${keyspace_info}"

  if [ "${header_count}" -ne 1 ]; then
    echo "ERROR: replica ${replica_fqdn} keyspace evidence is malformed — refusing bootstrap." >&2
    return 1
  fi
  return 0
}

validate_replica_function_state_empty() {
  local replica_fqdn="$1"
  local function_list
  if ! function_list=$(get_replica_function_list "${replica_fqdn}"); then
    echo "ERROR: replica ${replica_fqdn} Function evidence is unreadable — refusing bootstrap." >&2
    return 1
  fi
  function_list="${function_list//$'\r'/}"
  if [ -n "${function_list}" ]; then
    echo "ERROR: replica ${replica_fqdn} retains persisted Function state — refusing bootstrap." >&2
    return 1
  fi
  return 0
}

resolve_master_host_to_roster_fqdn() {
  local master_host="$1"
  if is_empty "${master_host}"; then
    echo "ERROR: replica upstream is empty." >&2
    return 1
  fi

  local matches=()
  local unique_fqdns=()
  local pod_fqdns=()
  local pod_fqdn known pod_ip

  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for pod_fqdn in "${pod_fqdns[@]}"; do
    if is_empty "${pod_fqdn}"; then
      echo "ERROR: data pod roster contains an empty FQDN." >&2
      return 1
    fi
    for known in "${unique_fqdns[@]}"; do
      if [ "${known}" = "${pod_fqdn}" ]; then
        echo "ERROR: data pod roster contains duplicate FQDN ${pod_fqdn}." >&2
        return 1
      fi
    done
    unique_fqdns+=("${pod_fqdn}")

    if [ "${master_host}" = "${pod_fqdn}" ] || \
       contains "${pod_fqdn}" "${master_host}."; then
      matches+=("${pod_fqdn}")
      continue
    fi

    pod_ip=$(getent hosts "${pod_fqdn}" 2>/dev/null | awk '{print $1}' | head -n1) || true
    if ! is_empty "${pod_ip}" && [ "${master_host}" = "${pod_ip}" ]; then
      matches+=("${pod_fqdn}")
    fi
  done

  if [ "${#matches[@]}" -ne 1 ]; then
    echo "ERROR: replica upstream '${master_host}' resolves to ${#matches[@]} roster members; expected exactly one." >&2
    return 1
  fi
  echo "${matches[0]}"
}

# A fresh lowest-ordinal pod can start after a faster peer has already become
# its replica. This is the only safe replica-present bootstrap view: every
# configured peer must be reachable as a replica, resolve to this exact pod,
# prove empty loaded keyspace and persisted Function state, and remain a
# replica of this pod when topology is re-read. Skipping an unreachable peer
# creates a blind window where surviving state can be overwritten.
validate_parallel_bootstrap_roster() {
  local expected_replicas="${COMPONENT_REPLICAS:-}"
  local pod_names=()
  local pod_fqdns=()
  local unique_names=()
  local unique_fqdns=()
  local pod_name pod_fqdn known matches current_matches=0

  case "${expected_replicas}" in
    ""|*[!0-9]*|0)
      echo "ERROR: invalid COMPONENT_REPLICAS '${expected_replicas:-<empty>}' — refusing bootstrap." >&2
      return 1
      ;;
  esac

  IFS=',' read -ra pod_names <<< "${VALKEY_POD_NAME_LIST}"
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  if [ "${#pod_names[@]}" -ne "${expected_replicas}" ] || \
     [ "${#pod_fqdns[@]}" -ne "${expected_replicas}" ]; then
    echo "ERROR: topology input count mismatch: COMPONENT_REPLICAS=${expected_replicas}, pod names=${#pod_names[@]}, pod FQDNs=${#pod_fqdns[@]} — refusing bootstrap." >&2
    return 1
  fi

  for pod_name in "${pod_names[@]}"; do
    if is_empty "${pod_name}"; then
      echo "ERROR: data pod name roster contains an empty entry — refusing bootstrap." >&2
      return 1
    fi
    for known in "${unique_names[@]}"; do
      if [ "${known}" = "${pod_name}" ]; then
        echo "ERROR: data pod name roster contains duplicate entry ${pod_name} — refusing bootstrap." >&2
        return 1
      fi
    done
    unique_names+=("${pod_name}")
    if [ "${pod_name}" = "${CURRENT_POD_NAME}" ]; then
      current_matches=$(( current_matches + 1 ))
    fi
  done
  if [ "${current_matches}" -ne 1 ]; then
    echo "ERROR: current pod ${CURRENT_POD_NAME:-<empty>} appears ${current_matches} time(s) in the data pod name roster; expected exactly one — refusing bootstrap." >&2
    return 1
  fi

  for pod_fqdn in "${pod_fqdns[@]}"; do
    if is_empty "${pod_fqdn}"; then
      echo "ERROR: data pod FQDN roster contains an empty entry — refusing bootstrap." >&2
      return 1
    fi
    for known in "${unique_fqdns[@]}"; do
      if [ "${known}" = "${pod_fqdn}" ]; then
        echo "ERROR: data pod FQDN roster contains duplicate entry ${pod_fqdn} — refusing bootstrap." >&2
        return 1
      fi
    done
    unique_fqdns+=("${pod_fqdn}")
  done

  for pod_name in "${pod_names[@]}"; do
    matches=0
    for pod_fqdn in "${pod_fqdns[@]}"; do
      case "${pod_fqdn}" in
        "${pod_name}".*) matches=$(( matches + 1 )) ;;
      esac
    done
    if [ "${matches}" -ne 1 ]; then
      echo "ERROR: data pod ${pod_name} maps to ${matches} FQDN roster entries; expected exactly one — refusing bootstrap." >&2
      return 1
    fi
  done
  for pod_fqdn in "${pod_fqdns[@]}"; do
    matches=0
    for pod_name in "${pod_names[@]}"; do
      case "${pod_fqdn}" in
        "${pod_name}".*) matches=$(( matches + 1 )) ;;
      esac
    done
    if [ "${matches}" -ne 1 ]; then
      echo "ERROR: data pod FQDN ${pod_fqdn} maps to ${matches} pod name roster entries; expected exactly one — refusing bootstrap." >&2
      return 1
    fi
  done
  return 0
}

validate_parallel_bootstrap_replica_view() {
  local expected_primary_fqdn="$1"
  local observed_replicas=0
  local pod_fqdns=()
  local pod_fqdn role master_host resolved_master rechecked_role rechecked_master rechecked_resolved_master
  local roster_primary_fqdn

  if ! validate_parallel_bootstrap_roster; then
    return 1
  fi
  if ! roster_primary_fqdn=$(resolve_master_host_to_roster_fqdn "${expected_primary_fqdn}"); then
    echo "ERROR: bootstrap candidate ${expected_primary_fqdn:-<empty>} is not unique in the data-pod roster — refusing bootstrap." >&2
    return 1
  fi
  if [ "${roster_primary_fqdn}" != "${expected_primary_fqdn}" ]; then
    echo "ERROR: bootstrap candidate ${expected_primary_fqdn} resolved to ${roster_primary_fqdn} — refusing bootstrap." >&2
    return 1
  fi

  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST}"
  for pod_fqdn in "${pod_fqdns[@]}"; do
    case "${pod_fqdn}" in
      "${CURRENT_POD_NAME}".*) continue ;;
    esac
    role=$(verify_pod_role "${pod_fqdn}") || true
    case "${role}" in
      "")
        echo "ERROR: bootstrap peer ${pod_fqdn} is unreachable — refusing bootstrap." >&2
        return 1
        ;;
      slave)
        observed_replicas=$(( observed_replicas + 1 ))
        master_host=$(get_replica_master_host "${pod_fqdn}") || true
        if is_empty "${master_host}"; then
          echo "ERROR: replica ${pod_fqdn} has no readable upstream — refusing bootstrap." >&2
          return 1
        fi
        if ! resolved_master=$(resolve_master_host_to_roster_fqdn "${master_host}"); then
          echo "ERROR: replica ${pod_fqdn} points outside an unambiguous data-pod roster — refusing bootstrap." >&2
          return 1
        fi
        if [ "${resolved_master}" != "${expected_primary_fqdn}" ]; then
          echo "ERROR: replica ${pod_fqdn} points to ${resolved_master}, not bootstrap candidate ${expected_primary_fqdn} — refusing conflicting replica targets." >&2
          return 1
        fi
        if ! validate_replica_keyspace_empty "${pod_fqdn}"; then
          return 1
        fi
        if ! validate_replica_function_state_empty "${pod_fqdn}"; then
          return 1
        fi
        rechecked_role=$(verify_pod_role "${pod_fqdn}") || true
        if [ "${rechecked_role}" != "slave" ]; then
          echo "ERROR: ${pod_fqdn} changed role during bootstrap validation (${rechecked_role:-unreachable}) — refusing bootstrap." >&2
          return 1
        fi
        rechecked_master=$(get_replica_master_host "${pod_fqdn}") || true
        if ! rechecked_resolved_master=$(resolve_master_host_to_roster_fqdn "${rechecked_master}"); then
          echo "ERROR: replica ${pod_fqdn} upstream changed during bootstrap validation — refusing bootstrap." >&2
          return 1
        fi
        if [ "${rechecked_resolved_master}" != "${expected_primary_fqdn}" ]; then
          echo "ERROR: replica ${pod_fqdn} upstream changed to ${rechecked_resolved_master} during bootstrap validation — refusing bootstrap." >&2
          return 1
        fi
        ;;
      master)
        echo "ERROR: ${pod_fqdn} became master during bootstrap validation — refusing a second primary." >&2
        return 1
        ;;
      *)
        echo "ERROR: ${pod_fqdn} reports unexpected replication role '${role}' — refusing bootstrap." >&2
        return 1
        ;;
    esac
  done

  # Re-read the complete peer roster at the success boundary. A peer validated
  # early in the first pass may change while a later peer is being inspected.
  for pod_fqdn in "${pod_fqdns[@]}"; do
    case "${pod_fqdn}" in
      "${CURRENT_POD_NAME}".*) continue ;;
    esac
    rechecked_role=$(verify_pod_role "${pod_fqdn}") || true
    if [ "${rechecked_role}" != "slave" ]; then
      echo "ERROR: ${pod_fqdn} changed role before bootstrap commit (${rechecked_role:-unreachable}) — refusing bootstrap." >&2
      return 1
    fi
    rechecked_master=$(get_replica_master_host "${pod_fqdn}") || true
    if ! rechecked_resolved_master=$(resolve_master_host_to_roster_fqdn "${rechecked_master}"); then
      echo "ERROR: replica ${pod_fqdn} upstream changed before bootstrap commit — refusing bootstrap." >&2
      return 1
    fi
    if [ "${rechecked_resolved_master}" != "${expected_primary_fqdn}" ]; then
      echo "ERROR: replica ${pod_fqdn} upstream changed to ${rechecked_resolved_master} before bootstrap commit — refusing bootstrap." >&2
      return 1
    fi
  done

  if [ "${observed_replicas}" -gt 0 ]; then
    echo "INFO: parallel cold-start replica view is consistent: all ${observed_replicas} configured peer(s) have empty keyspace and Function state and stably point to ${expected_primary_fqdn}." >&2
  fi
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
  local master_host
  master_host=$(get_replica_master_host "${slave_fqdn}") || true
  is_empty "${master_host}" && return 0
  resolve_master_host_to_roster_fqdn "${master_host}" || true
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
