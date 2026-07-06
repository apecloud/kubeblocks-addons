#!/bin/bash
# post-restore-sentinel.sh — postReady phase: verify the restored cluster
# converged, and re-arm Sentinel monitoring when credentials allow.
#
# After restore the Sentinel conf is empty (Sentinel has its own PVC which
# was not backed up). Sentinel monitor re-registration is owned by TWO
# mechanisms, selected by credential availability:
#
#   1. SENTINEL_PASSWORD available (user passed it through the restore env,
#      e.g. Cluster spec.restore.parameters
#      dataprotection.kubeblocks.io/restore-env): this script registers the
#      discovered primary with every Sentinel pod, fail-closed — restore
#      only succeeds when all expected Sentinels are configured.
#
#   2. SENTINEL_PASSWORD NOT available (the default: KubeBlocks
#      DataProtection injects only the data-component account into postReady
#      jobs; there is no API channel for cross-component credentials): this
#      script CANNOT authenticate to Sentinel — every Sentinel command would
#      fail with NOAUTH. Instead it verifies data-plane convergence (a
#      primary exists and the restored replicas are attached) using the
#      data credentials it does have, and delegates Sentinel monitor
#      registration to the Sentinel startup self-discovery loop
#      (valkey-sentinel-start.sh registers the discovered master with the
#      full failover tunables and it owns the Sentinel credentials).
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

set -e
set -o pipefail

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
data_port="${DP_DB_PORT:-6379}"
primary_discovery_retries="${POST_RESTORE_PRIMARY_DISCOVERY_RETRIES:-24}"
primary_discovery_interval="${POST_RESTORE_PRIMARY_DISCOVERY_INTERVAL_SECONDS:-5}"
convergence_retries="${POST_RESTORE_CONVERGENCE_RETRIES:-24}"
convergence_interval="${POST_RESTORE_CONVERGENCE_INTERVAL_SECONDS:-5}"

positive_int_or_default() {
  local value="$1" fallback="$2"
  case "${value}" in
    ''|*[!0-9]*) echo "${fallback}" ;;
    *) [ "${value}" -gt 0 ] && echo "${value}" || echo "${fallback}" ;;
  esac
}

positive_int_or_empty() {
  local value="$1"
  case "${value}" in
    ''|*[!0-9]*) return 1 ;;
    *) [ "${value}" -gt 0 ] && echo "${value}" || return 1 ;;
  esac
}

# Detect TLS via connection probe on the data pod.
# Restore jobs do not mount the TLS volume (it may not exist in non-TLS
# clusters), so probe: try plain first, then --tls --insecure.
detect_tls_args() {
  _tls_args=()
  local _probe_base=(valkey-cli --no-auth-warning -h "${DP_DB_HOST}" -p "${data_port}")
  [ -n "${DP_DB_PASSWORD:-}" ] && _probe_base+=(-a "${DP_DB_PASSWORD}")
  if ! "${_probe_base[@]}" PING 2>/dev/null | grep -q "PONG"; then
    if "${_probe_base[@]}" --tls --insecure PING 2>/dev/null | grep -q "PONG"; then
      _tls_args=(--tls --insecure)
      echo "INFO: TLS detected via connection probe — using --tls --insecure"
    fi
  fi
}

# ── derive naming convention ─────────────────────────────────────────────────
# DP_TARGET_POD_NAME / DP_TARGET_NAMESPACE are not guaranteed in postReady jobs.
# Fall back to parsing DP_DB_HOST:
#   <pod>.<headless>.<namespace>.svc.<cluster-domain>
derive_target_context() {
  pod_name="${DP_TARGET_POD_NAME}"
  namespace="${DP_TARGET_NAMESPACE}"
  if [ -z "${pod_name}" ] || [ -z "${namespace}" ]; then
    local host_parts
    host_parts=$(echo "${DP_DB_HOST}" | tr '.' '\n')
    [ -z "${pod_name}" ] && pod_name=$(echo "${host_parts}" | sed -n '1p')
    [ -z "${namespace}" ] && namespace=$(echo "${host_parts}" | sed -n '3p')
  fi

  if [ -z "${namespace}" ] && [ -r /var/run/secrets/kubernetes.io/serviceaccount/namespace ]; then
    namespace=$(cat /var/run/secrets/kubernetes.io/serviceaccount/namespace)
  fi

  if [ -z "${pod_name}" ] || [ -z "${namespace}" ]; then
    echo "ERROR: could not derive target pod naming context from DP_TARGET_* or DP_DB_HOST='${DP_DB_HOST}'" >&2
    return 1
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

  local sentinel_comp_name="${SENTINEL_COMPONENT_NAME:-valkey-sentinel}"
  sentinel_comp="${cluster_prefix}-${sentinel_comp_name}"
  sentinel_headless="${sentinel_comp}-headless.${namespace}.svc.${cluster_domain}"
  # Use full component name as master-name (matches register-to-sentinel logic)
  master_name="${comp_prefix}"
  comp_headless="${comp_prefix}-headless.${namespace}.svc.${cluster_domain}"
}

# ── find current primary ─────────────────────────────────────────────────────
# Also records every reachable data pod FQDN in reachable_data_fqdns so the
# convergence check knows how many replicas to expect.
find_primary_fqdn() {
  local default_scan_limit="${POST_RESTORE_DATA_SCAN_LIMIT:-16}"
  default_scan_limit=$(positive_int_or_default "${default_scan_limit}" 16)
  local max_ordinal="${DATA_REPLICA_COUNT:-${default_scan_limit}}"
  max_ordinal=$(positive_int_or_default "${max_ordinal}" "${default_scan_limit}")
  local ordinal=0 fqdn role consecutive_unreachable=0 primary=""
  reachable_data_fqdns=()
  while [ "${ordinal}" -lt "${max_ordinal}" ]; do
    fqdn="${comp_prefix}-${ordinal}.${comp_headless}"
    ordinal=$((ordinal + 1))

    role=$("${data_cli_base[@]}" -h "${fqdn}" ROLE 2>/dev/null | head -1 | tr -d '\r\n') || true
    if [ -z "${role}" ]; then
      role=$("${data_cli_base[@]}" -h "${fqdn}" INFO replication 2>/dev/null \
               | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
    fi

    if [ -z "${role}" ]; then
      consecutive_unreachable=$((consecutive_unreachable + 1))
      [ "${consecutive_unreachable}" -ge 2 ] && break
      continue
    fi
    consecutive_unreachable=0
    reachable_data_fqdns+=("${fqdn}")
    if [ "${role}" = "master" ] && [ -z "${primary}" ]; then
      primary="${fqdn}"
    fi
  done
  if [ -n "${primary}" ]; then
    echo "${primary}"
    return 0
  fi
  return 1
}

discover_primary() {
  primary_fqdn=""
  local attempt=1
  while [ "${attempt}" -le "${primary_discovery_retries}" ]; do
    primary_fqdn=$(find_primary_fqdn) || true
    if [ -n "${primary_fqdn}" ]; then
      echo "INFO: current primary is ${primary_fqdn}"
      return 0
    fi

    if [ "${attempt}" -lt "${primary_discovery_retries}" ]; then
      echo "INFO: primary not discoverable yet, retrying (${attempt}/${primary_discovery_retries}) after ${primary_discovery_interval}s"
      sleep "${primary_discovery_interval}"
    fi
    attempt=$((attempt + 1))
  done

  echo "ERROR: could not find primary among data pods after ${primary_discovery_retries} attempts — restore convergence failed." >&2
  return 1
}

# ── data-plane convergence check (no Sentinel credentials needed) ────────────
# Poll the discovered primary until it reports role:master and at least the
# explicitly expected restored replica count attached. A partial discovery set
# must not become the success contract, because postReady can run before every
# restored replica is reachable. For HA restores without Sentinel credentials,
# pass DATA_REPLICA_COUNT (or POST_RESTORE_DATA_EXPECTED_COUNT) via restore-env.
resolve_expected_data_pod_count() {
  local configured_count="${POST_RESTORE_DATA_EXPECTED_COUNT:-${DATA_REPLICA_COUNT:-}}"
  if [ -n "${configured_count}" ]; then
    expected_data_pod_count=$(positive_int_or_empty "${configured_count}") || {
      echo "ERROR: expected data pod count must be a positive integer, got '${configured_count}'." >&2
      return 1
    }
    return 0
  fi

  local sentinel_endpoint_count=0
  sentinel_endpoint_count=$(getent hosts "${sentinel_headless}" 2>/dev/null | awk '!seen[$1]++ {c++} END {print c+0}') || sentinel_endpoint_count=0
  if [ "${sentinel_endpoint_count}" -gt 0 ]; then
    echo "ERROR: Sentinel endpoints exist but DATA_REPLICA_COUNT/POST_RESTORE_DATA_EXPECTED_COUNT is not set; refusing to infer restored replica convergence from a partial data scan." >&2
    return 1
  fi

  expected_data_pod_count="${#reachable_data_fqdns[@]}"
}

verify_replication_converged() {
  local expected_data_pod_count expected_replicas
  resolve_expected_data_pod_count || return 1
  expected_replicas=$(( expected_data_pod_count - 1 ))
  [ "${expected_replicas}" -lt 0 ] && expected_replicas=0
  local attempt=1
  while [ "${attempt}" -le "${convergence_retries}" ]; do
    local repl_info role connected
    repl_info=$("${data_cli_base[@]}" -h "${primary_fqdn}" INFO replication 2>/dev/null) || repl_info=""
    role=$(echo "${repl_info}" | grep "^role:" | tr -d '\r\n' | cut -d: -f2) || true
    connected=$(echo "${repl_info}" | grep "^connected_slaves:" | tr -d '\r\n' | cut -d: -f2) || true
    connected=$(positive_int_or_default "${connected}" 0)
    if [ "${role}" = "master" ] && [ "${connected}" -ge "${expected_replicas}" ]; then
      echo "INFO: replication converged — ${primary_fqdn} is master with ${connected}/${expected_replicas} expected replicas attached."
      return 0
    fi
    echo "INFO: waiting for replication convergence (role='${role:-unreachable}', connected_slaves=${connected}/${expected_replicas}, attempt ${attempt}/${convergence_retries})"
    if [ "${attempt}" -lt "${convergence_retries}" ]; then
      sleep "${convergence_interval}"
    fi
    attempt=$((attempt + 1))
  done
  echo "ERROR: replication did not converge within $((convergence_retries * convergence_interval))s — restore postReady failed." >&2
  return 1
}

# ── Sentinel registration (requires SENTINEL_PASSWORD) ──────────────────────
# SENTINEL_POD_FQDN_LIST is the authoritative target set when supplied.
# Otherwise, the Sentinel headless service DNS endpoints are the runtime target
# set available to this DataProtection job, and the expected count comes from
# the chart's default Sentinel replicas contract. Restore must not report
# success after configuring only a guessed or partial subset of Sentinel pods.
build_sentinel_target_list() {
  sentinel_fqdn_list=()
  expected_sentinel_count=""
  if [ -n "${SENTINEL_POD_FQDN_LIST:-}" ]; then
    local sentinel_fqdn_list_raw=()
    IFS=',' read -ra sentinel_fqdn_list_raw <<< "${SENTINEL_POD_FQDN_LIST}"
    local sentinel_fqdn
    for sentinel_fqdn in "${sentinel_fqdn_list_raw[@]}"; do
      [ -n "${sentinel_fqdn}" ] && sentinel_fqdn_list+=("${sentinel_fqdn}")
    done
    expected_sentinel_count="${#sentinel_fqdn_list[@]}"
    if [ "${expected_sentinel_count}" -eq 0 ]; then
      echo "ERROR: SENTINEL_POD_FQDN_LIST is set but empty after parsing." >&2
      return 1
    fi
    echo "INFO: using SENTINEL_POD_FQDN_LIST (${expected_sentinel_count} entries) as target set."
  else
    # PR #2988 semantics: when POST_RESTORE_SENTINEL_EXPECTED_COUNT is
    # explicitly set, the DNS-discovered count must match exactly. When
    # unset, the DNS-discovered count is used — this assumes component
    # orchestration guarantees all Sentinel pods are Ready before postReady
    # runs; if that assumption fails (e.g. node eviction during restore),
    # the explicit env var is the safety net. Even-count discovery is
    # refused as a signal of partial visibility.
    local local_dns_attempt=0
    local sentinel_ip _rest
    while [ "${local_dns_attempt}" -lt 3 ]; do
      sentinel_fqdn_list=()
      while read -r sentinel_ip _rest; do
        [ -n "${sentinel_ip}" ] && sentinel_fqdn_list+=("${sentinel_ip}")
      done < <(getent hosts "${sentinel_headless}" 2>/dev/null | awk '!seen[$1]++ { print $1 }')
      [ "${#sentinel_fqdn_list[@]}" -gt 0 ] && break
      local_dns_attempt=$((local_dns_attempt + 1))
      echo "INFO: DNS returned 0 Sentinel endpoints, retrying (${local_dns_attempt}/3)..."
      sleep 5
    done
    local discovered_sentinel_count="${#sentinel_fqdn_list[@]}"
    if [ "${discovered_sentinel_count}" -eq 0 ]; then
      echo "ERROR: discovered 0 Sentinel endpoint(s) from ${sentinel_headless} after retries; cannot proceed." >&2
      return 1
    fi
    if [ -n "${POST_RESTORE_SENTINEL_EXPECTED_COUNT:-}" ]; then
      expected_sentinel_count=$(positive_int_or_default "${POST_RESTORE_SENTINEL_EXPECTED_COUNT}" 3)
      if [ "${discovered_sentinel_count}" -ne "${expected_sentinel_count}" ]; then
        echo "ERROR: discovered ${discovered_sentinel_count}/${expected_sentinel_count} expected Sentinel endpoint(s) from ${sentinel_headless}; refusing partial post-restore registration." >&2
        return 1
      fi
      echo "INFO: using ${discovered_sentinel_count}/${expected_sentinel_count} DNS-discovered Sentinel endpoint(s) from ${sentinel_headless} as target set."
    else
      if [ $((discovered_sentinel_count % 2)) -eq 0 ]; then
        echo "ERROR: DNS discovered ${discovered_sentinel_count} Sentinel endpoint(s) — even count suggests partial discovery from an odd-replica deployment. Set POST_RESTORE_SENTINEL_EXPECTED_COUNT explicitly in your restore env to proceed safely (e.g. POST_RESTORE_SENTINEL_EXPECTED_COUNT=3 or =5)." >&2
        return 1
      fi
      expected_sentinel_count="${discovered_sentinel_count}"
      echo "WARNING: Sentinel expected count inferred from DNS (${discovered_sentinel_count}). For HA restores, explicitly set POST_RESTORE_SENTINEL_EXPECTED_COUNT in restore env to guarantee full-cluster registration."
      echo "INFO: using ${discovered_sentinel_count} DNS-discovered Sentinel endpoint(s) from ${sentinel_headless} as target set."
    fi
  fi
}

register_sentinels_with_credentials() {
  local reachable_sentinel_fqdn_list=()
  local failed_sentinel_count=0
  local consecutive_unreachable=0
  local sentinel_fqdn response
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
    return 1
  fi

  if [ -n "${expected_sentinel_count}" ] && [ "${#reachable_sentinel_fqdn_list[@]}" -lt "${expected_sentinel_count}" ]; then
    echo "ERROR: reached ${#reachable_sentinel_fqdn_list[@]}/${expected_sentinel_count} expected Sentinel pods." >&2
    return 1
  fi

  local sentinel_count
  if [ -n "${expected_sentinel_count}" ]; then
    sentinel_count="${expected_sentinel_count}"
  else
    sentinel_count="${#reachable_sentinel_fqdn_list[@]}"
  fi
  local sentinel_monitor_quorum=$(( sentinel_count / 2 + 1 ))
  echo "INFO: using Sentinel monitor quorum ${sentinel_monitor_quorum}/${sentinel_count}."

  local configured_sentinel_count=0
  local sentinel_configured existing monitor_out sentinel_set_out
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
    return 1
  fi

  if [ -n "${expected_sentinel_count}" ] && [ "${configured_sentinel_count}" -lt "${expected_sentinel_count}" ]; then
    echo "ERROR: configured ${configured_sentinel_count}/${expected_sentinel_count} expected Sentinel pods." >&2
    return 1
  fi

  if [ "${failed_sentinel_count}" -gt 0 ]; then
    echo "INFO: Sentinel registration completed with ${configured_sentinel_count} configured and ${failed_sentinel_count} skipped/failed."
  else
    echo "INFO: Sentinel registration completed with ${configured_sentinel_count} configured."
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ─────────────────────────────────────────────────────────────────────
detect_tls_args

# Build a valkey-cli prefix for the data nodes
data_cli_base=(valkey-cli --no-auth-warning "${_tls_args[@]}" -p "${data_port}")
[ -n "${DP_DB_PASSWORD:-}" ] && data_cli_base+=(-a "${DP_DB_PASSWORD}")

# Build a sentinel cli prefix
sentinel_cli_base=(valkey-cli --no-auth-warning "${_tls_args[@]}" -p "${sentinel_port}")
[ -n "${SENTINEL_PASSWORD:-}" ] && sentinel_cli_base+=(-a "${SENTINEL_PASSWORD}")

derive_target_context || exit 1
discover_primary || exit 1

if [ -n "${SENTINEL_PASSWORD:-}" ]; then
  # Fail-closed registration path: credentials were explicitly provided
  # (restore env), so this job is responsible for re-arming every Sentinel.
  build_sentinel_target_list || exit 1
  register_sentinels_with_credentials || exit 1
else
  # No Sentinel credentials in this execution face. Verify data-plane
  # convergence with the data credentials we do have; Sentinel monitor
  # registration is delegated to the Sentinel startup self-discovery loop
  # (valkey-sentinel-start.sh), which owns the Sentinel credentials and
  # applies the same failover tunables.
  echo "INFO: SENTINEL_PASSWORD not provided — verifying data-plane convergence; Sentinel monitor registration is delegated to the Sentinel self-discovery loop."
  verify_replication_converged || exit 1
fi
