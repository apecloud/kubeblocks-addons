#!/bin/bash
# valkey-register-to-sentinel.sh — postProvision action.
#
# Runs on the initial primary pod (targetPodSelector: Role / matchingKey: primary).
# Registers the primary with every Sentinel pod so that automatic failover is active.
#
# KubeBlocks injects:
#   CURRENT_POD_NAME          — name of this (primary) pod
#   CURRENT_POD_IP            — pod IP
#   CURRENT_POD_HOST_IP       — node IP
#   VALKEY_COMPONENT_NAME     — used as the Sentinel master-name
#   VALKEY_POD_NAME_LIST      — comma-separated list of data pod names
#   VALKEY_POD_FQDN_LIST      — comma-separated list of data pod FQDNs
#   SENTINEL_POD_FQDN_LIST    — comma-separated list of Sentinel pod FQDNs
#   SENTINEL_SERVICE_PORT     — Sentinel port (default 26379)
#   SENTINEL_PASSWORD         — Sentinel auth password (may be empty)
#   VALKEY_DEFAULT_PASSWORD   — data node auth password (may be empty)
#   VALKEY_ADVERTISED_PORT    — NodePort mapping (optional)
#   SERVICE_PORT              — data node port (default 6379)

set -e
# shellcheck source=/dev/null
source /scripts/common.sh

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
data_port="${SERVICE_PORT:-6379}"
master_name="${VALKEY_COMPONENT_NAME}"

# ── determine the address Sentinel should use to reach this primary ──────────

primary_host=""
primary_port="${data_port}"

# NodePort path
if ! is_empty "${VALKEY_ADVERTISED_PORT}"; then
  local_ordinal=$(extract_obj_ordinal "${CURRENT_POD_NAME}")
  for entry in $(echo "${VALKEY_ADVERTISED_PORT}" | tr ',' '\n'); do
    svc_name="${entry%%:*}"
    svc_port="${entry##*:}"
    if [ "$(extract_obj_ordinal "${svc_name}")" = "${local_ordinal}" ]; then
      primary_host="${CURRENT_POD_HOST_IP}"
      primary_port="${svc_port}"
      break
    fi
  done
fi

# Fall back to pod FQDN
if is_empty "${primary_host}"; then
  primary_host=$(get_target_pod_fqdn_from_pod_fqdn_vars \
                   "${VALKEY_POD_FQDN_LIST}" "${CURRENT_POD_NAME}")
  if is_empty "${primary_host}"; then
    echo "ERROR: cannot resolve FQDN for ${CURRENT_POD_NAME}" >&2
    exit 1
  fi
fi

echo "Primary address for Sentinel registration: ${primary_host}:${primary_port}"

# ── helper: build a Sentinel CLI command prefix ──────────────────────────────

sentinel_cli() {
  local host="${1}"
  local cmd="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h ${host} -p ${sentinel_port}"
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    cmd="${cmd} -a ${SENTINEL_PASSWORD}"
  fi
  echo "${cmd}"
}

# ── helper: run one sentinel sub-command and verify "OK" ────────────────────

execute_sentinel_cmd() {
  local host="${1}"
  shift
  local cli output
  cli=$(sentinel_cli "${host}")
  output=$(${cli} "$@" 2>&1) || { echo "sentinel cmd failed: ${output}" >&2; return 1; }
  if [ "${output}" != "OK" ]; then
    echo "Unexpected sentinel response: ${output}" >&2
    return 1
  fi
}

# ── helper: check connectivity ───────────────────────────────────────────────

check_sentinel_connectivity() {
  local host="${1}"
  local cli
  cli=$(sentinel_cli "${host}")
  ${cli} PING 2>/dev/null | grep -q "PONG"
}

check_data_connectivity() {
  local cmd="valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h ${primary_host} -p ${primary_port}"
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    cmd="${cmd} -a ${VALKEY_DEFAULT_PASSWORD}"
  fi
  ${cmd} PING 2>/dev/null | grep -q "PONG"
}

# ── register with one Sentinel pod ──────────────────────────────────────────

register_to_one_sentinel() {
  local sentinel_fqdn="${1}"
  echo "--- Registering with Sentinel ${sentinel_fqdn} ---"

  call_func_with_retry 5 5 check_sentinel_connectivity "${sentinel_fqdn}" || {
    echo "ERROR: Sentinel ${sentinel_fqdn} not reachable" >&2
    return 1
  }
  call_func_with_retry 5 5 check_data_connectivity || {
    echo "ERROR: primary ${primary_host}:${primary_port} not reachable" >&2
    return 1
  }

  local cli
  cli=$(sentinel_cli "${sentinel_fqdn}")

  # Check if already monitored
  # get-master-addr-by-name returns "(nil)" when master is not registered,
  # which is non-empty so must be checked explicitly.
  local master_addr
  master_addr=$(${cli} SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null || true)
  if is_empty "${master_addr}" || [ "${master_addr}" = "(nil)" ]; then
    echo "Sentinel not yet monitoring '${master_name}' — issuing SENTINEL monitor..."
    call_func_with_retry 3 5 execute_sentinel_cmd "${sentinel_fqdn}" \
      SENTINEL monitor "${master_name}" "${primary_host}" "${primary_port}" 2 || return 1
  else
    echo "Sentinel already monitoring '${master_name}' at ${master_addr}. Skipping monitor."
  fi

  # Configure parameters
  call_func_with_retry 3 5 execute_sentinel_cmd "${sentinel_fqdn}" \
    SENTINEL set "${master_name}" down-after-milliseconds 20000 || return 1
  call_func_with_retry 3 5 execute_sentinel_cmd "${sentinel_fqdn}" \
    SENTINEL set "${master_name}" failover-timeout 60000 || return 1
  call_func_with_retry 3 5 execute_sentinel_cmd "${sentinel_fqdn}" \
    SENTINEL set "${master_name}" parallel-syncs 1 || return 1

  # Data node auth
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    call_func_with_retry 3 5 execute_sentinel_cmd "${sentinel_fqdn}" \
      SENTINEL set "${master_name}" auth-user "${VALKEY_DEFAULT_USER:-default}" || return 1
    call_func_with_retry 3 5 execute_sentinel_cmd "${sentinel_fqdn}" \
      SENTINEL set "${master_name}" auth-pass "${VALKEY_DEFAULT_PASSWORD}" || return 1
  fi

  echo "Registration with Sentinel ${sentinel_fqdn} succeeded."
}

# ── main ─────────────────────────────────────────────────────────────────────

if is_empty "${SENTINEL_COMPONENT_NAME}"; then
  echo "No Sentinel component found — standalone topology, nothing to register."
  exit 0
fi

if is_empty "${SENTINEL_POD_FQDN_LIST}"; then
  echo "ERROR: SENTINEL_POD_FQDN_LIST is not set." >&2
  exit 1
fi

IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
for fqdn in "${sentinel_fqdns[@]}"; do
  register_to_one_sentinel "${fqdn}" || exit 1
done

echo "All Sentinel pods registered successfully."
