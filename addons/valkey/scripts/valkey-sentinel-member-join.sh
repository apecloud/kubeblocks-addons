#!/bin/bash
# valkey-sentinel-member-join.sh — memberJoin action of the Sentinel component.
#
# KubeBlocks calls this action on the pod that just joined the component
# (scale-out of the Sentinel component).  A brand-new Sentinel starts with an
# empty state: it does not know the master, so it neither counts for quorum nor
# can it vote in an election until a monitor stanza exists.  This script
# registers the current data primary with the *local* Sentinel through the
# dynamic SENTINEL MONITOR / SENTINEL SET commands.  Peer Sentinels learn about
# the new node through the Sentinel pub/sub HELLO channel, so no
# cross-registration is needed here.
#
# The tunables applied below are the same ones used by the two existing
# registration paths (valkey-register-to-sentinel.sh on the data side and
# _register_monitor in valkey-sentinel-start.sh), so failover timing does not
# depend on which path happened to run first.
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
#   VALKEY_ADVERTISED_PORT     — NodePort mapping of the data pods (optional)
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
# same style as valkey-member-leave.sh / valkey-sentinel-start.sh.  The
# identity values below (master name, local Sentinel host) are read *inside*
# the functions instead, so a unit test can change them per case.
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
data_port="${SERVICE_PORT:-6379}"

# local_sentinel_host — the Sentinel pod to register into.  This action runs on
# the pod that just joined, so it is always the pod itself; KubeBlocks injects
# KB_JOIN_MEMBER_POD_FQDN for memberJoin actions.  Loopback keeps the script
# usable outside of a lifecycle action (local debugging / unit tests).
local_sentinel_host() {
  echo "${KB_JOIN_MEMBER_POD_FQDN:-127.0.0.1}"
}

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
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

build_sentinel_cli() {
  local host="${1}"
  _sentinel_cli_cmd=(valkey-cli --no-auth-warning -h "${host}" -p "${sentinel_port}")
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    _sentinel_cli_cmd+=(-a "${SENTINEL_PASSWORD}")
  fi
  if ! is_empty "${VALKEY_CLI_TLS_ARGS}"; then
    # shellcheck disable=SC2206
    _sentinel_cli_cmd+=(${VALKEY_CLI_TLS_ARGS})
  fi
}

sentinel_ping_ok() {
  build_sentinel_cli "$(local_sentinel_host)"
  "${_sentinel_cli_cmd[@]}" PING 2>/dev/null | grep -q "PONG"
}

# probe_role <pod_fqdn> — prints the engine role reported by that data pod
# ("master"/"slave"), or an empty string when the pod is unreachable.
probe_role() {
  local fqdn="${1}"
  build_data_cli "${fqdn}"
  "${_data_cli_cmd[@]}" INFO replication 2>/dev/null \
    | grep "^role:" | tr -d '\r\n' | cut -d: -f2
}

# resolve_primary_fqdn — probe every data pod and return the FQDN of the one
# that reports role:master.
#
# Probing beats assuming "the first pod is the primary": after a failover the
# primary is whatever Sentinel promoted, which may be any pod.  When no data
# pod answers yet (data component still starting) fall back to the
# min-lexicographical pod — the deterministic primary used by the very first
# registration (same rule as valkey-register-to-sentinel.sh).
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

# resolve_monitor_address <primary_fqdn> — print "<host> <port>" to monitor.
#
# NodePort deployments must register the same address the data side registers
# (node_ip:nodeport), otherwise Sentinel hands clients a different master
# address than the one used during the initial registration.  Any node IP
# serves a NodePort, so CURRENT_POD_HOST_IP (this Sentinel's node) is valid.
# Without NodePort the in-cluster pod FQDN is used, exactly like
# valkey-register-to-sentinel.sh and valkey-sentinel-start.sh.
resolve_monitor_address() {
  local primary_fqdn="${1}"
  local host="" port="${data_port}"

  if ! is_empty "${VALKEY_ADVERTISED_PORT}"; then
    local primary_pod primary_ordinal entry svc_name svc_port
    primary_pod="${primary_fqdn%%.*}"
    primary_ordinal=$(extract_obj_ordinal "${primary_pod}")
    for entry in $(echo "${VALKEY_ADVERTISED_PORT}" | tr ',' '\n'); do
      svc_name="${entry%%:*}"
      svc_port="${entry##*:}"
      if [ "$(extract_obj_ordinal "${svc_name}")" = "${primary_ordinal}" ]; then
        host="${CURRENT_POD_HOST_IP}"
        port="${svc_port}"
        break
      fi
    done
  fi

  if is_empty "${host}"; then
    host="${primary_fqdn}"
  fi
  echo "${host} ${port}"
}

# calculate_sentinel_monitor_quorum — quorum of the current Sentinel set.
# Same rule as valkey-sentinel-start.sh: majority of the Sentinel pods, so a
# scale-out (3 → 5) tightens the quorum from 2 to 3.
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

# monitored_master_address — current answer of the local Sentinel for the
# master name.  Empty / "(nil)" means "not monitored yet" (get-master-addr-by-name
# returns "(nil)" which is a non-empty string, hence the explicit check).
monitored_master_address() {
  build_sentinel_cli "$(local_sentinel_host)"
  "${_sentinel_cli_cmd[@]}" SENTINEL get-master-addr-by-name "${VALKEY_COMPONENT_NAME}" 2>/dev/null \
    | head -n1 | tr -d '\r\n' || true
}

sentinel_set_or_fail() {
  local option="${1}"
  local output
  output=$("${_sentinel_cli_cmd[@]}" SENTINEL SET "${VALKEY_COMPONENT_NAME}" "$@" 2>&1) || true
  output="${output//$'\r'/}"
  if [ "${output}" != "OK" ]; then
    echo "ERROR: SENTINEL SET ${VALKEY_COMPONENT_NAME} ${option} returned '${output:-<empty>}'." >&2
    return 1
  fi
}

# register_master_locally <primary_host> <primary_port>
register_master_locally() {
  local primary_host="${1}"
  local primary_port="${2}"
  local quorum current_address

  quorum=$(calculate_sentinel_monitor_quorum) || return 1

  # The Sentinel process may still be starting up on a freshly scheduled pod.
  call_func_with_retry 3 5 sentinel_ping_ok || {
    echo "ERROR: local Sentinel $(local_sentinel_host):${sentinel_port} is not answering PING." >&2
    return 1
  }
  build_sentinel_cli "$(local_sentinel_host)"

  current_address=$(monitored_master_address)
  if is_empty "${current_address}" || [ "${current_address}" = "(nil)" ]; then
    echo "INFO: registering ${VALKEY_COMPONENT_NAME} at ${primary_host}:${primary_port} (quorum ${quorum})."
    "${_sentinel_cli_cmd[@]}" SENTINEL MONITOR "${VALKEY_COMPONENT_NAME}" \
      "${primary_host}" "${primary_port}" "${quorum}" >/dev/null || {
      echo "ERROR: SENTINEL MONITOR ${VALKEY_COMPONENT_NAME} failed." >&2
      return 1
    }
  else
    echo "INFO: local Sentinel already monitors ${VALKEY_COMPONENT_NAME} at ${current_address}, skip SENTINEL MONITOR."
  fi

  sentinel_set_or_fail down-after-milliseconds 20000 || return 1
  sentinel_set_or_fail failover-timeout 60000 || return 1
  sentinel_set_or_fail parallel-syncs 1 || return 1
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    sentinel_set_or_fail auth-user "${VALKEY_DEFAULT_USER:-default}" || return 1
    sentinel_set_or_fail auth-pass "${VALKEY_DEFAULT_PASSWORD}" || return 1
  fi

  # Verify the registration took effect: SENTINEL MONITOR can fail transiently
  # (e.g. DNS not ready) and still return without a non-zero exit code.
  current_address=$(monitored_master_address)
  if is_empty "${current_address}" || [ "${current_address}" = "(nil)" ]; then
    echo "ERROR: local Sentinel still has no master '${VALKEY_COMPONENT_NAME}' after registration." >&2
    return 1
  fi
  echo "Registered ${VALKEY_COMPONENT_NAME} at ${current_address} with the local Sentinel."
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
load_common_library

if is_empty "${VALKEY_COMPONENT_NAME}"; then
  echo "ERROR: VALKEY_COMPONENT_NAME is not set — cannot register a Sentinel monitor." >&2
  exit 1
fi

primary_fqdn=$(resolve_primary_fqdn) || exit 1
read -r monitor_host monitor_port <<< "$(resolve_monitor_address "${primary_fqdn}")"

register_master_locally "${monitor_host}" "${monitor_port}" || exit 1
