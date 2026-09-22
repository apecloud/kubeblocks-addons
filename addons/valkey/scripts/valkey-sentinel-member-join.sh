#!/bin/bash

# shellcheck disable=SC2207

# valkey-sentinel-member-join.sh — memberJoin action of the Sentinel component.
#
# A close port of the redis addon's redis-sentinel-member-join.sh: when a new
# Sentinel pod joins (scale-out), it registers the current data primary with
# its *local* Sentinel via SENTINEL MONITOR / SENTINEL SET.  Peer Sentinels
# learn about the new node through the pub/sub HELLO channel, so no
# cross-registration is needed here.
#
# The master address must match what the data side registered
# (valkey-register-to-sentinel.sh): node_ip:NodePort for NodePort deployments,
# the pod FQDN otherwise.  CURRENT_POD_HOST_IP for the node IP comes from the
# shared lifecycle-action env declared on the ComponentDefinition
# (memberJoin.exec.env) — KubeBlocks merges every action's env onto the kbagent
# sidecar, which executes this script; the fieldRef envs of the
# valkey-sentinel container itself are NOT visible here (this bit us once: with
# the env missing the address degraded to the pod FQDN, which a Sentinel
# without `sentinel resolve-hostnames yes` rejects, and valkey-cli's exit code
# does not reflect the rejected MONITOR).
#
# Deltas vs the redis script (documented, both already covered by tests):
#   - the primary is located by probing role:master across the data pods,
#     falling back to the min-lexicographical pod (redis assumes min-lex); the
#     probe survives failovers where the min-lex pod is a replica;
#   - the monitor quorum is the majority of the current Sentinel set
#     (count / 2 + 1, redis hardcodes 2), so a 3 -> 5 scale-out tightens it;
#   - the SENTINEL MONITOR reply is compared against "OK" instead of relying
#     on the exit code: valkey-cli in non-interactive mode exits 0 even when
#     the server answers with an error reply.
#
# KubeBlocks injects for memberJoin:
#   KB_JOIN_MEMBER_POD_NAME    — name of the joining Sentinel pod
#   KB_JOIN_MEMBER_POD_FQDN    — FQDN of the joining Sentinel pod
# Component vars used:
#   VALKEY_COMPONENT_NAME      — data component name; also the Sentinel master-name
#   VALKEY_POD_FQDN_LIST       — data pod FQDNs (primary lookup by role probe)
#   VALKEY_POD_NAME_LIST       — data pod names (fallback primary lookup)
#   VALKEY_DEFAULT_USER        — data node ACL user (auth-user of the monitor)
#   VALKEY_DEFAULT_PASSWORD    — data node password (auth-pass of the monitor)
#   VALKEY_ADVERTISED_PORT     — NodePort mapping of the data pods ("svc:port,...")
#   VALKEY_LB_ADVERTISED_PORT  — LoadBalancer port of the data pods (optional)
#   VALKEY_LB_ADVERTISED_HOST  — LoadBalancer host list of the data pods (optional)
#   SERVICE_PORT               — data node port (default 6379)
#   SENTINEL_POD_FQDN_LIST     — Sentinel peers; monitor quorum = count/2 + 1
#   SENTINEL_PASSWORD          — Sentinel auth password (may be empty)
#   SENTINEL_SERVICE_PORT      — Sentinel port (default 26379)
#   VALKEY_CLI_TLS_ARGS        — TLS flags for valkey-cli (may be empty)
#
# Fail-closed: a Sentinel that joins without a monitor stanza cannot vote, so
# every failure path exits non-zero instead of reporting success.

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

# Ports are constant for the pod, so they are resolved once at load time — the
# same style as valkey-sentinel-start.sh.
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
data_port="${SERVICE_PORT:-6379}"

valkey_announce_host_value=""
valkey_announce_port_value=""

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

extract_lb_host_by_svc_name() {
  local svc_name="$1"
  local lb_composed_name
  for lb_composed_name in $(echo "${VALKEY_LB_ADVERTISED_HOST}" | tr ',' '\n'); do
    if [[ ${lb_composed_name} == *":"* ]]; then
      if [[ ${lb_composed_name%%:*} == "$svc_name" ]]; then
        echo "${lb_composed_name#*:}"
        break
      fi
    else
      break
    fi
  done
}

# parse_valkey_primary_announce_addr <primary_pod_name> — resolve the
# advertised "<host> <port>" of that data pod into the globals
# valkey_announce_host_value / valkey_announce_port_value.  LoadBalancer hosts
# take precedence over the node IP (redis parity).
parse_valkey_primary_announce_addr() {
  local pod_name="$1"
  if is_empty "${VALKEY_ADVERTISED_PORT}"; then
    VALKEY_ADVERTISED_PORT="${VALKEY_LB_ADVERTISED_PORT}"
  fi
  if is_empty "${VALKEY_ADVERTISED_PORT}"; then
    echo "Environment variable VALKEY_ADVERTISED_PORT not found. Ignoring."
    return 0
  fi

  local found="false"
  local pod_name_ordinal
  pod_name_ordinal=$(extract_obj_ordinal "${pod_name}")
  # the value format of VALKEY_ADVERTISED_PORT is "pod1Svc:advertisedPort1,pod2Svc:advertisedPort2,..."
  # Plain bash IFS splits instead of kblib's split()/equals(): common.sh
  # shipped by older addon builds does not carry those helpers, and a missing
  # function falls through to the coreutils split binary, which explodes on
  # the FQDN ("cannot open '<fqdn>' for reading").
  local advertised_ports advertised_port svc_name port svc_name_ordinal lb_host
  IFS=',' read -ra advertised_ports <<< "${VALKEY_ADVERTISED_PORT}"
  for advertised_port in "${advertised_ports[@]}"; do
    local parts
    IFS=':' read -ra parts <<< "${advertised_port}"
    svc_name="${parts[0]}"
    port="${parts[1]}"
    svc_name_ordinal=$(extract_obj_ordinal "${svc_name}")
    if [[ "${svc_name_ordinal}" == "${pod_name_ordinal}" ]]; then
      echo "Found matching svcName and port for podName '${pod_name}', VALKEY_ADVERTISED_PORT: ${VALKEY_ADVERTISED_PORT}. svcName: ${svc_name}, port: ${port}."
      valkey_announce_port_value="${port}"
      lb_host=$(extract_lb_host_by_svc_name "${svc_name}")
      if [ -n "${lb_host}" ]; then
        echo "Found load balancer host for svcName '${svc_name}', value is '${lb_host}'."
        valkey_announce_host_value="${lb_host}"
        valkey_announce_port_value="${data_port}"
      else
        valkey_announce_host_value="${CURRENT_POD_HOST_IP}"
      fi
      found="true"
      break
    fi
  done

  if [ "${found}" = "false" ]; then
    echo "Error: No matching svcName and port found for podName '${pod_name}', VALKEY_ADVERTISED_PORT: ${VALKEY_ADVERTISED_PORT}. Exiting." >&2
    return 1
  fi
}

# resolve_primary_fqdn — probe every data pod and return the FQDN of the one
# that reports role:master; falls back to the min-lexicographical pod (the
# deterministic primary of the very first registration, same rule as
# valkey-register-to-sentinel.sh) when no data pod answers yet.
resolve_primary_fqdn() {
  local pod_fqdns=() fqdn role
  IFS=',' read -ra pod_fqdns <<< "${VALKEY_POD_FQDN_LIST:-}"
  for fqdn in "${pod_fqdns[@]}"; do
    [ -z "${fqdn}" ] && continue
    role=$(probe_role "${fqdn}") || true
    if [ "${role}" = "master" ]; then
      echo "${fqdn}"
      return 0
    fi
  done

  local fallback_pod="" fallback_fqdn=""
  fallback_pod=$(min_lexicographical_order_pod "${VALKEY_POD_NAME_LIST:-}") || true
  if ! is_empty "${fallback_pod}"; then
    fallback_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars \
                      "${VALKEY_POD_FQDN_LIST:-}" "${fallback_pod}") || true
    if ! is_empty "${fallback_fqdn}"; then
      echo "WARNING: no data pod reported role:master — falling back to ${fallback_pod}." >&2
      echo "${fallback_fqdn}"
      return 0
    fi
  fi

  echo "ERROR: cannot determine the primary of ${VALKEY_COMPONENT_NAME} — refusing to register a guessed address." >&2
  return 1
}

# probe_role <pod_fqdn> — prints the engine role reported by that data pod
# ("master"/"slave"), or an empty string when the pod is unreachable.
probe_role() {
  local fqdn="${1}"
  build_data_cli "${fqdn}"
  "${_data_cli_cmd[@]}" INFO replication 2>/dev/null \
    | grep "^role:" | tr -d '\r\n' | cut -d: -f2
}

build_data_cli() {
  local host="${1}"
  _data_cli_cmd=(valkey-cli --no-auth-warning -h "${host}" -p "${data_port}")
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    _data_cli_cmd+=(-a "${VALKEY_DEFAULT_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    _data_cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

# calculate_sentinel_monitor_quorum — quorum of the current Sentinel set.
# Majority of the Sentinel pods (count / 2 + 1), same rule as
# valkey-sentinel-start.sh, so a scale-out (3 → 5) tightens the quorum from 2
# to 3.
calculate_sentinel_monitor_quorum() {
  local sentinel_fqdns=() fqdn count=0
  IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST:-}"
  for fqdn in "${sentinel_fqdns[@]}"; do
    [ -n "${fqdn}" ] && count=$((count + 1))
  done
  if [ "${count}" -eq 0 ]; then
    echo "ERROR: SENTINEL_POD_FQDN_LIST is empty — cannot compute the monitor quorum." >&2
    return 1
  fi
  echo $(( count / 2 + 1 ))
}

# register_master_to_sentinel <name> <ip> <port> <quorum>
#                             <down-after-ms> <failover-timeout> <parallel-syncs>
#
# Register the master to the local sentinel with dynamic commands.
# Sentinel does not reload the configuration file at runtime and CONFIG REWRITE
# would overwrite manual file changes, so the master must be registered via
# SENTINEL MONITOR/SET commands which take effect immediately.
register_master_to_sentinel() {
  local master_name="$1"
  local master_ip="$2"
  local master_port="$3"
  local master_quorum="$4"
  local master_down_after_milliseconds="$5"
  local master_failover_timeout="$6"
  local master_parallel_syncs="$7"

  local sentinel_cli_cmd="valkey-cli ${VALKEY_CLI_TLS_ARGS} -h $(local_sentinel_host) -p ${sentinel_port}"
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    sentinel_cli_cmd="${sentinel_cli_cmd} -a ${SENTINEL_PASSWORD}"
  fi

  unset_xtrace_when_ut_mode_false
  local master_addr
  master_addr=$(${sentinel_cli_cmd} SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null | head -n1 | tr -d '\r\n')
  if is_empty "${master_addr}" || [ "${master_addr}" = "(nil)" ]; then
    # The reply MUST be checked against "OK": valkey-cli exits 0 even when the
    # server answers with an error reply (e.g. "ERR Invalid IP address or
    # hostname specified" for an FQDN while resolve-hostnames is off).
    local monitor_reply
    monitor_reply=$(${sentinel_cli_cmd} SENTINEL MONITOR "${master_name}" "${master_ip}" "${master_port}" "${master_quorum}" 2>&1) || true
    monitor_reply="${monitor_reply//$'\r'/}"
    if [ "${monitor_reply}" != "OK" ]; then
      echo "failed to register master ${master_name} to local sentinel: SENTINEL MONITOR returned '${monitor_reply:-<empty>}'" >&2
      return 1
    fi
  else
    echo "master ${master_name} is already monitored, skip SENTINEL MONITOR"
  fi
  ${sentinel_cli_cmd} SENTINEL SET "${master_name}" down-after-milliseconds "${master_down_after_milliseconds}" || return 1
  ${sentinel_cli_cmd} SENTINEL SET "${master_name}" failover-timeout "${master_failover_timeout}" || return 1
  ${sentinel_cli_cmd} SENTINEL SET "${master_name}" parallel-syncs "${master_parallel_syncs}" || return 1
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    ${sentinel_cli_cmd} SENTINEL SET "${master_name}" auth-user "${VALKEY_DEFAULT_USER:-default}" || return 1
    ${sentinel_cli_cmd} SENTINEL SET "${master_name}" auth-pass "${VALKEY_DEFAULT_PASSWORD}" || return 1
  fi
  set_xtrace_when_ut_mode_false
  echo "register master ${master_name} to local sentinel succeeded!"
}

# local_sentinel_host — the Sentinel pod to register into.  This action runs on
# the pod that just joined, so it is always the pod itself; KubeBlocks injects
# KB_JOIN_MEMBER_POD_FQDN for memberJoin actions.  Loopback keeps the script
# usable outside of a lifecycle action (local debugging / unit tests).
local_sentinel_host() {
  echo "${KB_JOIN_MEMBER_POD_FQDN:-127.0.0.1}"
}

recover_registered_valkey_servers() {
  # check required environment variables, we use VALKEY_COMPONENT_NAME as the master name registered to sentinel
  if is_empty "${VALKEY_COMPONENT_NAME}" || is_empty "${VALKEY_POD_NAME_LIST}" || is_empty "${VALKEY_POD_FQDN_LIST}"; then
    echo "Error: Required environment variable VALKEY_COMPONENT_NAME, VALKEY_POD_NAME_LIST and VALKEY_POD_FQDN_LIST is not set." >&2
    return 1
  fi

  # locate the current primary: probe role:master first, fall back to the
  # minimum lexicographical order pod name (the same logic as
  # valkey-register-to-sentinel.sh)
  local valkey_primary_pod_name valkey_primary_pod_fqdn
  valkey_primary_pod_fqdn=$(resolve_primary_fqdn) || return 1
  valkey_primary_pod_name="${valkey_primary_pod_fqdn%%.*}"

  parse_valkey_primary_announce_addr "${valkey_primary_pod_name}" || return 1

  local master_name
  if is_empty "${CUSTOM_SENTINEL_MASTER_NAME}"; then
    master_name="${VALKEY_COMPONENT_NAME}"
  else
    master_name="${CUSTOM_SENTINEL_MASTER_NAME}"
  fi

  local master_ip="${valkey_primary_pod_fqdn}"
  local master_port="${data_port}"
  if ! is_empty "${valkey_announce_host_value}" && ! is_empty "${valkey_announce_port_value}"; then
    master_ip="${valkey_announce_host_value}"
    master_port="${valkey_announce_port_value}"
  fi

  local master_quorum
  master_quorum=$(calculate_sentinel_monitor_quorum) || return 1

  if ! register_master_to_sentinel "${master_name}" "${master_ip}" "${master_port}" \
        "${master_quorum}" "20000" "60000" "1"; then
    echo "register master ${master_name} failed" >&2
    return 1
  fi
}

recover_registered_valkey_servers_if_needed() {
  echo "horizontal scaling"
  if ! recover_registered_valkey_servers; then
    echo "recover_registered_valkey_servers failed"
    exit 1
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library

recover_registered_valkey_servers_if_needed

# Sync the Sentinel ACL from an established peer: valkey-sentinel-start.sh
# writes only the "default" user from SENTINEL_PASSWORD, so custom accounts
# added to the fleet later must be pushed to the joining pod explicitly
# (Sentinel does not replicate ACLs between peers).  Fail-closed: a Sentinel
# with a stale ACL would reject authenticated clients after a restart.
# The path is overridable for the unit tests.
SYNC_ACL_SCRIPT="${SENTINEL_SYNC_ACL_SCRIPT:-/scripts/valkey-sentinel-sync-acl.sh}"
if ! bash "${SYNC_ACL_SCRIPT}"; then
  echo "ERROR: sentinel ACL sync failed — see the output above." >&2
  exit 1
fi
echo "sentinel ACL sync succeeded."
