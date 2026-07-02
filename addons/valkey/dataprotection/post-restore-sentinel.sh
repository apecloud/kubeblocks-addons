#!/bin/bash
# post-restore-sentinel.sh — postReady phase: re-register the primary with
# all Sentinel pods after a full cluster restore.
#
# After restore the Sentinel conf is empty (Sentinel has its own PVC which
# was not backed up).  This script discovers the current primary among the
# data pods and issues SENTINEL monitor + configuration commands on every
# Sentinel pod, restoring HA monitoring.
#
# KubeBlocks DataProtection injects:
#   DP_TARGET_POD_NAME   — name of the restored target pod (e.g. ns-valkey-0)
#   DP_TARGET_NAMESPACE  — Kubernetes namespace
#   DP_DB_HOST           — FQDN of the target pod
#   DP_DB_PORT           — data port
#   DP_DB_PASSWORD       — data node auth password
#
# The script derives Sentinel pod FQDNs from the naming convention:
#   data pod:     <cluster>-<comp>-<n>
#   sentinel comp: <cluster>-valkey-sentinel  (standard topology name)
#
# Current BackupPolicyTemplate env schema cannot inject cross-component
# Sentinel credentials. The chart currently supports exactly 3 Sentinel
# replicas, so the DNS fallback has an independent expected count.

set -e
set -o pipefail

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
data_port="${DP_DB_PORT:-6379}"
primary_discovery_retries="${POST_RESTORE_PRIMARY_DISCOVERY_RETRIES:-24}"
primary_discovery_interval="${POST_RESTORE_PRIMARY_DISCOVERY_INTERVAL_SECONDS:-5}"

positive_int_or_default() {
  local value="$1" fallback="$2"
  case "${value}" in
    ''|*[!0-9]*) echo "${fallback}" ;;
    *) [ "${value}" -gt 0 ] && echo "${value}" || echo "${fallback}" ;;
  esac
}

# Detect TLS via connection probe on the data pod.
# Restore jobs do not mount the TLS volume (it may not exist in non-TLS clusters).
_tls_args=()
_probe_base=(valkey-cli --no-auth-warning -h "${DP_DB_HOST}" -p "${data_port}")
[ -n "${DP_DB_PASSWORD:-}" ] && _probe_base+=(-a "${DP_DB_PASSWORD}")
if ! "${_probe_base[@]}" PING 2>/dev/null | grep -q "PONG"; then
  if "${_probe_base[@]}" --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
    _tls_args=(--tls --insecure)
    echo "INFO: TLS detected via connection probe — using --tls --insecure"
  fi
fi

# Build a valkey-cli prefix for the data nodes
data_cli_base=(valkey-cli --no-auth-warning "${_tls_args[@]}" -p "${data_port}")
[ -n "${DP_DB_PASSWORD:-}" ] && data_cli_base+=(-a "${DP_DB_PASSWORD}")

# Build a sentinel cli prefix
sentinel_cli_base=(valkey-cli --no-auth-warning "${_tls_args[@]}" -p "${sentinel_port}")
[ -n "${SENTINEL_PASSWORD:-}" ] && sentinel_cli_base+=(-a "${SENTINEL_PASSWORD}")

# ── derive naming convention ─────────────────────────────────────────────────
# DP_TARGET_POD_NAME / DP_TARGET_NAMESPACE are not guaranteed in postReady jobs.
# Fall back to parsing DP_DB_HOST:
#   <pod>.<headless>.<namespace>.svc.<cluster-domain>
pod_name="${DP_TARGET_POD_NAME}"
namespace="${DP_TARGET_NAMESPACE}"
if [ -z "${pod_name}" ] || [ -z "${namespace}" ]; then
  host_parts=$(echo "${DP_DB_HOST}" | tr '.' '\n')
  [ -z "${pod_name}" ] && pod_name=$(echo "${host_parts}" | sed -n '1p')
  [ -z "${namespace}" ] && namespace=$(echo "${host_parts}" | sed -n '3p')
fi

if [ -z "${namespace}" ] && [ -r /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
  namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
fi

if [ -z "${pod_name}" ] || [ -z "${namespace}" ]; then
  echo "ERROR: could not derive target pod naming context from DP_TARGET_* or DP_DB_HOST='${DP_DB_HOST}'" >&2
  exit 1
fi

# Strip trailing "-<digits>" to get "<cluster>-<component>"
comp_prefix="${pod_name%-*}"           # e.g. mycluster-valkey
cluster_prefix="${comp_prefix%-*}"     # e.g. mycluster
if [ -n "${CLUSTER_DOMAIN:-}" ]; then
  cluster_domain="${CLUSTER_DOMAIN}"
else
  cluster_domain=$(echo "${DP_DB_HOST}" | sed -n 's/.*\.svc\.\(.*\)$/\1/p')
  cluster_domain="${cluster_domain:-cluster.local}"
fi

echo "INFO: resolved target context pod=${pod_name} namespace=${namespace} comp=${comp_prefix}"

sentinel_comp_name="${SENTINEL_COMPONENT_NAME:-valkey-sentinel}"
sentinel_comp="${cluster_prefix}-${sentinel_comp_name}"
sentinel_headless="${sentinel_comp}-headless.${namespace}.svc.${cluster_domain}"
# Use full component name as master-name (matches register-to-sentinel logic)
master_name="${comp_prefix}"

# ── find current primary ─────────────────────────────────────────────────────
comp_headless="${comp_prefix}-headless.${namespace}.svc.${cluster_domain}"

find_primary_fqdn() {
  local default_scan_limit="${POST_RESTORE_DATA_SCAN_LIMIT:-16}"
  default_scan_limit=$(positive_int_or_default "${default_scan_limit}" 16)
  local max_ordinal="${DATA_REPLICA_COUNT:-${default_scan_limit}}"
  max_ordinal=$(positive_int_or_default "${max_ordinal}" "${default_scan_limit}")
  local ordinal=0 fqdn role consecutive_unreachable=0
  while [ "${ordinal}" -lt "${max_ordinal}" ]; do
    fqdn="${comp_prefix}-${ordinal}.${comp_headless}"
    ordinal=$((ordinal + 1))

    role=$("${data_cli_base[@]}" -h "${fqdn}" ROLE 2>/dev/null | head -1 | tr -d '\r\n') || true
    if [ "${role}" = "master" ]; then
      echo "${fqdn}"
      return 0
    fi

    role=$("${data_cli_base[@]}" -h "${fqdn}" INFO replication 2>/dev/null \
             | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
    if [ "${role}" = "master" ]; then
      echo "${fqdn}"
      return 0
    fi

    if [ -z "${role}" ]; then
      consecutive_unreachable=$((consecutive_unreachable + 1))
      [ "${consecutive_unreachable}" -ge 2 ] && break
    else
      consecutive_unreachable=0
    fi
  done
  return 1
}

primary_fqdn=""
attempt=1
while [ "${attempt}" -le "${primary_discovery_retries}" ]; do
  primary_fqdn=$(find_primary_fqdn) || true
  if [ -n "${primary_fqdn}" ]; then
    echo "INFO: current primary is ${primary_fqdn}"
    break
  fi

  if [ "${attempt}" -lt "${primary_discovery_retries}" ]; then
    echo "INFO: primary not discoverable yet, retrying (${attempt}/${primary_discovery_retries}) after ${primary_discovery_interval}s"
    sleep "${primary_discovery_interval}"
  fi
  attempt=$((attempt + 1))
done

if [ -z "${primary_fqdn}" ]; then
  echo "ERROR: could not find primary among data pods after ${primary_discovery_retries} attempts — Sentinel registration failed." >&2
  exit 1
fi

# ── register primary with each Sentinel pod ──────────────────────────────────
# SENTINEL_POD_FQDN_LIST is the authoritative target set when supplied.
# Otherwise, the Sentinel headless service DNS endpoints are the runtime target
# set available to this DataProtection job, and the expected count comes from
# the chart's fixed Sentinel replicas contract. Restore must not report success
# after configuring only a guessed or partial subset of Sentinel pods.
sentinel_fqdn_list=()
expected_sentinel_count=""
if [ -n "${SENTINEL_POD_FQDN_LIST:-}" ]; then
  sentinel_fqdn_list_raw=()
  IFS=',' read -ra sentinel_fqdn_list_raw <<< "${SENTINEL_POD_FQDN_LIST}"
  for sentinel_fqdn in "${sentinel_fqdn_list_raw[@]}"; do
    [ -n "${sentinel_fqdn}" ] && sentinel_fqdn_list+=("${sentinel_fqdn}")
  done
  expected_sentinel_count="${#sentinel_fqdn_list[@]}"
  if [ "${expected_sentinel_count}" -eq 0 ]; then
    echo "ERROR: SENTINEL_POD_FQDN_LIST is set but empty after parsing." >&2
    exit 1
  fi
  echo "INFO: using SENTINEL_POD_FQDN_LIST (${expected_sentinel_count} entries) as target set."
else
  expected_sentinel_count=$(positive_int_or_default "${POST_RESTORE_SENTINEL_EXPECTED_COUNT:-3}" 3)
  while read -r sentinel_ip _; do
    [ -n "${sentinel_ip}" ] && sentinel_fqdn_list+=("${sentinel_ip}")
  done < <(getent hosts "${sentinel_headless}" 2>/dev/null | awk '!seen[$1]++ { print $1 }')
  discovered_sentinel_count="${#sentinel_fqdn_list[@]}"
  if [ "${discovered_sentinel_count}" -ne "${expected_sentinel_count}" ]; then
    echo "ERROR: discovered ${discovered_sentinel_count}/${expected_sentinel_count} expected Sentinel endpoint(s) from ${sentinel_headless}; refusing partial post-restore registration." >&2
    exit 1
  fi
  echo "INFO: using ${discovered_sentinel_count}/${expected_sentinel_count} DNS-discovered Sentinel endpoint(s) from ${sentinel_headless} as target set."
fi

reachable_sentinel_fqdn_list=()
failed_sentinel_count=0
consecutive_unreachable=0
for sentinel_fqdn in "${sentinel_fqdn_list[@]}"; do

  # Check connectivity
  response=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" PING 2>/dev/null) || {
    echo "INFO: Sentinel ${sentinel_fqdn} not reachable, skipping."
    if [ -n "${expected_sentinel_count}" ]; then
      failed_sentinel_count=$((failed_sentinel_count + 1))
      continue
    fi
    consecutive_unreachable=$((consecutive_unreachable + 1))
    [ "${consecutive_unreachable}" -ge 2 ] && [ "${#reachable_sentinel_fqdn_list[@]}" -gt 0 ] && break
    continue
  }
  response=$(printf '%s' "${response}" | tr -d '\r\n')
  if [ "${response}" != "PONG" ]; then
    echo "WARNING: Sentinel ${sentinel_fqdn} returned unexpected PING response: ${response}" >&2
    failed_sentinel_count=$((failed_sentinel_count + 1))
    continue
  fi
  consecutive_unreachable=0
  reachable_sentinel_fqdn_list+=("${sentinel_fqdn}")
done

if [ "${#reachable_sentinel_fqdn_list[@]}" -eq 0 ]; then
  echo "ERROR: no Sentinel pod was reachable; postReady cannot report restore success." >&2
  exit 1
fi

if [ -n "${expected_sentinel_count}" ] && [ "${#reachable_sentinel_fqdn_list[@]}" -lt "${expected_sentinel_count}" ]; then
  echo "ERROR: reached ${#reachable_sentinel_fqdn_list[@]}/${expected_sentinel_count} expected Sentinel pods." >&2
  exit 1
fi

if [ -n "${expected_sentinel_count}" ]; then
  sentinel_count="${expected_sentinel_count}"
else
  sentinel_count="${#reachable_sentinel_fqdn_list[@]}"
fi
sentinel_monitor_quorum=$(( sentinel_count / 2 + 1 ))
echo "INFO: using Sentinel monitor quorum ${sentinel_monitor_quorum}/${sentinel_count}."

configured_sentinel_count=0
for sentinel_fqdn in "${reachable_sentinel_fqdn_list[@]}"; do
  sentinel_configured=1

  # Check if already monitoring
  # get-master-addr-by-name returns "(nil)" when master is not registered,
  # which is non-empty so must be checked explicitly.
  existing=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" \
               SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null) || true
  existing=$(printf '%s' "${existing}" | tr -d '\r')
  if [ -z "${existing}" ] || [ "${existing}" = "(nil)" ]; then
    echo "INFO: Registering master '${master_name}' (${primary_fqdn}:${data_port}) with ${sentinel_fqdn}"
    monitor_out=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" \
      SENTINEL monitor "${master_name}" "${primary_fqdn}" "${data_port}" "${sentinel_monitor_quorum}" 2>&1) || {
      echo "ERROR: SENTINEL monitor command failed on ${sentinel_fqdn}: ${monitor_out}" >&2
      sentinel_configured=0
    }
    monitor_out=$(printf '%s' "${monitor_out}" | tr -d '\r\n')
    if [ "${monitor_out}" != "OK" ]; then
      echo "ERROR: SENTINEL monitor unexpected response from ${sentinel_fqdn}: ${monitor_out}" >&2
      sentinel_configured=0
    fi
  else
    echo "INFO: Sentinel ${sentinel_fqdn} already monitors '${master_name}' — updating config."
  fi

  # Apply standard configuration
  # valkey-cli exits 0 even for server errors; capture output and check content.
  sentinel_set_out=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" SENTINEL set "${master_name}" down-after-milliseconds 20000 2>&1) || true
  sentinel_set_out=$(printf '%s' "${sentinel_set_out}" | tr -d '\r\n')
  [ "${sentinel_set_out}" != "OK" ] && { echo "ERROR: failed to set down-after-milliseconds on ${sentinel_fqdn}: ${sentinel_set_out}" >&2; sentinel_configured=0; }
  sentinel_set_out=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" SENTINEL set "${master_name}" failover-timeout 60000 2>&1) || true
  sentinel_set_out=$(printf '%s' "${sentinel_set_out}" | tr -d '\r\n')
  [ "${sentinel_set_out}" != "OK" ] && { echo "ERROR: failed to set failover-timeout on ${sentinel_fqdn}: ${sentinel_set_out}" >&2; sentinel_configured=0; }
  sentinel_set_out=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" SENTINEL set "${master_name}" parallel-syncs 1 2>&1) || true
  sentinel_set_out=$(printf '%s' "${sentinel_set_out}" | tr -d '\r\n')
  [ "${sentinel_set_out}" != "OK" ] && { echo "ERROR: failed to set parallel-syncs on ${sentinel_fqdn}: ${sentinel_set_out}" >&2; sentinel_configured=0; }
  if [ -n "${DP_DB_PASSWORD:-}" ]; then
    sentinel_set_out=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" SENTINEL set "${master_name}" auth-user "${DP_DB_USER:-default}" 2>&1) || true
    sentinel_set_out=$(printf '%s' "${sentinel_set_out}" | tr -d '\r\n')
    [ "${sentinel_set_out}" != "OK" ] && { echo "ERROR: failed to set auth-user on ${sentinel_fqdn}: ${sentinel_set_out}" >&2; sentinel_configured=0; }
    sentinel_set_out=$("${sentinel_cli_base[@]}" -h "${sentinel_fqdn}" SENTINEL set "${master_name}" auth-pass "${DP_DB_PASSWORD}" 2>&1) || true
    sentinel_set_out=$(printf '%s' "${sentinel_set_out}" | tr -d '\r\n')
    [ "${sentinel_set_out}" != "OK" ] && { echo "ERROR: failed to set auth-pass on ${sentinel_fqdn}: ${sentinel_set_out}" >&2; sentinel_configured=0; }
  fi

  if [ "${sentinel_configured}" -eq 1 ]; then
    configured_sentinel_count=$((configured_sentinel_count + 1))
    echo "INFO: Sentinel ${sentinel_fqdn} configured."
  else
    failed_sentinel_count=$((failed_sentinel_count + 1))
  fi
done

if [ "${configured_sentinel_count}" -eq 0 ]; then
  echo "ERROR: no Sentinel pod was configured; postReady cannot report restore success." >&2
  exit 1
fi

if [ -n "${expected_sentinel_count}" ] && [ "${configured_sentinel_count}" -lt "${expected_sentinel_count}" ]; then
  echo "ERROR: configured ${configured_sentinel_count}/${expected_sentinel_count} expected Sentinel pods." >&2
  exit 1
fi

if [ "${failed_sentinel_count}" -gt 0 ]; then
  echo "INFO: Sentinel registration completed with ${configured_sentinel_count} configured and ${failed_sentinel_count} skipped/failed."
else
  echo "INFO: Sentinel registration completed with ${configured_sentinel_count} configured."
fi
