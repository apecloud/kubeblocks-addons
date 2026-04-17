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
# SENTINEL_SERVICE_PORT and SENTINEL_PASSWORD must be injected via the
# BackupPolicyTemplate env section if Sentinel auth is enabled.

set -e
set -o pipefail

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
data_port="${DP_DB_PORT:-6379}"

# Detect TLS via connection probe on the data pod.
# Restore jobs do not mount the TLS volume (it may not exist in non-TLS clusters).
_tls_args=""
_probe_base="valkey-cli --no-auth-warning -h ${DP_DB_HOST} -p ${data_port}"
[ -n "${DP_DB_PASSWORD}" ] && _probe_base="${_probe_base} -a ${DP_DB_PASSWORD}"
if ! ${_probe_base} PING 2>/dev/null | grep -q "PONG"; then
  if ${_probe_base} --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
    _tls_args="--tls --insecure"
    echo "INFO: TLS detected via connection probe — using --tls --insecure"
  fi
fi

# Build a valkey-cli prefix for the data nodes
if [ -n "${DP_DB_PASSWORD}" ]; then
  data_cli_base="valkey-cli --no-auth-warning ${_tls_args} -p ${data_port} -a ${DP_DB_PASSWORD}"
else
  data_cli_base="valkey-cli --no-auth-warning ${_tls_args} -p ${data_port}"
fi

# Build a sentinel cli prefix
if [ -n "${SENTINEL_PASSWORD}" ]; then
  sentinel_cli_base="valkey-cli --no-auth-warning ${_tls_args} -p ${sentinel_port} -a ${SENTINEL_PASSWORD}"
else
  sentinel_cli_base="valkey-cli --no-auth-warning ${_tls_args} -p ${sentinel_port}"
fi

# ── derive naming convention ─────────────────────────────────────────────────
# DP_TARGET_POD_NAME = "<cluster>-<component>-<ordinal>"
# Strip trailing "-<digits>" to get "<cluster>-<component>"
pod_name="${DP_TARGET_POD_NAME}"
comp_prefix="${pod_name%-*}"           # e.g. mycluster-valkey
cluster_prefix="${comp_prefix%-*}"     # e.g. mycluster
namespace="${DP_TARGET_NAMESPACE}"
cluster_domain="${CLUSTER_DOMAIN:-cluster.local}"

# Sentinel component name follows the ClusterDefinition topology:
# component name "valkey-sentinel" → pod name "<cluster>-valkey-sentinel-<n>"
sentinel_comp="${cluster_prefix}-valkey-sentinel"
sentinel_headless="${sentinel_comp}-headless.${namespace}.svc.${cluster_domain}"
# Use full component name as master-name (matches register-to-sentinel logic)
master_name="${comp_prefix}"

# ── find current primary ─────────────────────────────────────────────────────
primary_fqdn=""
comp_headless="${comp_prefix}-headless.${namespace}.svc.${cluster_domain}"

for ordinal in 0 1 2 3 4; do
  fqdn="${comp_prefix}-${ordinal}.${comp_headless}"
  role=$(${data_cli_base} -h "${fqdn}" INFO replication 2>/dev/null \
           | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || continue
  if [ "${role}" = "master" ]; then
    primary_fqdn="${fqdn}"
    echo "INFO: current primary is ${primary_fqdn}"
    break
  fi
done

if [ -z "${primary_fqdn}" ]; then
  echo "ERROR: could not find primary among data pods — Sentinel registration failed." >&2
  exit 1
fi

# ── register primary with each Sentinel pod ──────────────────────────────────
# Allow override via SENTINEL_REPLICA_COUNT; default to 3.
sentinel_replica_count="${SENTINEL_REPLICA_COUNT:-3}"
ordinal=0
while [ "${ordinal}" -lt "${sentinel_replica_count}" ]; do
  sentinel_fqdn="${sentinel_comp}-${ordinal}.${sentinel_headless}"
  ordinal=$((ordinal + 1))

  # Check connectivity
  response=$(${sentinel_cli_base} -h "${sentinel_fqdn}" PING 2>/dev/null) || {
    echo "INFO: Sentinel ${sentinel_fqdn} not reachable, skipping."
    continue
  }
  [ "${response}" != "PONG" ] && { echo "INFO: Sentinel ${sentinel_fqdn} not ready, skipping."; continue; }

  # Check if already monitoring
  # get-master-addr-by-name returns "(nil)" when master is not registered,
  # which is non-empty so must be checked explicitly.
  existing=$(${sentinel_cli_base} -h "${sentinel_fqdn}" \
               SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null) || true
  if [ -z "${existing}" ] || [ "${existing}" = "(nil)" ]; then
    echo "INFO: Registering master '${master_name}' (${primary_fqdn}:${data_port}) with ${sentinel_fqdn}"
    monitor_out=$(${sentinel_cli_base} -h "${sentinel_fqdn}" \
      SENTINEL monitor "${master_name}" "${primary_fqdn}" "${data_port}" 2 2>&1) || {
      echo "WARNING: SENTINEL monitor command failed on ${sentinel_fqdn}: ${monitor_out}" >&2
      continue
    }
    if [ "${monitor_out}" != "OK" ]; then
      echo "WARNING: SENTINEL monitor unexpected response from ${sentinel_fqdn}: ${monitor_out}" >&2
    fi
  else
    echo "INFO: Sentinel ${sentinel_fqdn} already monitors '${master_name}' — updating config."
  fi

  # Apply standard configuration
  # valkey-cli exits 0 even for server errors; capture output and check content.
  sentinel_set_out=$(${sentinel_cli_base} -h "${sentinel_fqdn}" SENTINEL set "${master_name}" down-after-milliseconds 20000 2>&1) || true
  [ "${sentinel_set_out}" != "OK" ] && echo "WARNING: failed to set down-after-milliseconds on ${sentinel_fqdn}: ${sentinel_set_out}" >&2
  sentinel_set_out=$(${sentinel_cli_base} -h "${sentinel_fqdn}" SENTINEL set "${master_name}" failover-timeout 60000 2>&1) || true
  [ "${sentinel_set_out}" != "OK" ] && echo "WARNING: failed to set failover-timeout on ${sentinel_fqdn}: ${sentinel_set_out}" >&2
  sentinel_set_out=$(${sentinel_cli_base} -h "${sentinel_fqdn}" SENTINEL set "${master_name}" parallel-syncs 1 2>&1) || true
  [ "${sentinel_set_out}" != "OK" ] && echo "WARNING: failed to set parallel-syncs on ${sentinel_fqdn}: ${sentinel_set_out}" >&2
  if [ -n "${DP_DB_PASSWORD}" ]; then
    sentinel_set_out=$(${sentinel_cli_base} -h "${sentinel_fqdn}" SENTINEL set "${master_name}" auth-user "${DP_DB_USER:-default}" 2>&1) || true
    [ "${sentinel_set_out}" != "OK" ] && echo "WARNING: failed to set auth-user on ${sentinel_fqdn}: ${sentinel_set_out}" >&2
    sentinel_set_out=$(${sentinel_cli_base} -h "${sentinel_fqdn}" SENTINEL set "${master_name}" auth-pass "${DP_DB_PASSWORD}" 2>&1) || true
    [ "${sentinel_set_out}" != "OK" ] && echo "WARNING: failed to set auth-pass on ${sentinel_fqdn}: ${sentinel_set_out}" >&2
  fi

  echo "INFO: Sentinel ${sentinel_fqdn} configured."
done   # end while ordinal < sentinel_replica_count

echo "INFO: Post-restore Sentinel registration complete."
