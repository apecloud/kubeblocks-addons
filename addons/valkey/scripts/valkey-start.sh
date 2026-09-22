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

# This pod's own announce address (replica-announce-ip/port), filled by
# build_announce_addr().  check_current_pod_is_primary() compares the pair a
# Sentinel reports against these values — the same advertised-mapping rule the
# redis addon uses in check_current_pod_is_primary().
valkey_announce_host_value=""
valkey_announce_port_value=""

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
  build_valkey_service_port

  # Step 3: TLS material — written here, not in the config template/store,
  # so the whole TLS switch lives in the start script (redis addon parity).
  build_valkey_tls_config

  # Step 4: announce IP/port for replication topology.
  # When using NodePort or LoadBalancer, replicas must announce the
  # external address so peers outside the cluster can connect.
  build_announce_addr

  # Step 5: replicaof — determine whether this pod is primary or secondary
  build_replicaof_config

  # Step 6: ACL / password
  rebuild_acl_file
  build_acl_entries
  echo "aclfile ${ACL_FILE}" >> "${CONF_RUNTIME}"
}

# build_valkey_service_port — the listening port.  TLS_ENABLED is the only
# switch (injected by the ComponentDefinition from tlsVarRef), exactly like the
# redis addon's build_redis_service_port: TLS on → the TLS port carries the
# service, TLS off → the plaintext port does.
build_valkey_service_port() {
  if [ "${TLS_ENABLED}" = "true" ]; then
    echo "tls-port ${service_port}" >> "${CONF_RUNTIME}"
  else
    echo "port ${service_port}" >> "${CONF_RUNTIME}"
  fi
}

# build_valkey_tls_config — the certificate material, appended only when TLS is
# enabled.  Nothing here is user-tunable through the config store: the paths
# must match the volume KubeBlocks mounts at TLS_MOUNT_PATH, and a config-file
# value could contradict it.  `port 0` turns the plaintext listener off so the
# TLS port is the only way in (same directives as redis-start.sh).
build_valkey_tls_config() {
  if [ "${TLS_ENABLED}" = "true" ]; then
    local tls_mount_path="${TLS_MOUNT_PATH:-/etc/pki/tls}"
    {
      echo "tls-cert-file ${tls_mount_path}/tls.crt"
      echo "tls-key-file ${tls_mount_path}/tls.key"
      echo "tls-ca-cert-file ${tls_mount_path}/ca.crt"
      echo "tls-auth-clients no"
      echo "tls-replication yes"
      echo "port 0"
    } >> "${CONF_RUNTIME}"
  fi
}

extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$VALKEY_LB_ADVERTISED_HOST" | tr ',' '\n' ); do
    if [[ ${lb_composed_name} == *":"* ]]; then
       if [[ ${lb_composed_name%:*} == "$svc_name" ]]; then
         echo "${lb_composed_name#*:}"
         break
       fi
    else
       break
    fi
  done
}

build_announce_addr() {
  # Prefer per-pod NodePort, then LoadBalancer, then FQDN.
  local announce_host=""
  local announce_port=""
  valkey_announce_host_value=""
  valkey_announce_port_value=""

  if is_empty "$VALKEY_ADVERTISED_PORT"; then
     VALKEY_ADVERTISED_PORT="$VALKEY_LB_ADVERTISED_PORT"
  fi
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
        lb_host=$(extract_lb_host_by_svc_name "$svc_name")
        if [ -n "$lb_host" ]; then
          echo "Found load balancer host for svcName '$svc_name', value is '$lb_host'."
          announce_host="$lb_host"
          announce_port="6379"
        else
          announce_host="$CURRENT_POD_HOST_IP"
        fi
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
    valkey_announce_host_value="${announce_host}"
    valkey_announce_port_value="${announce_port}"
  fi
}

build_replicaof_config() {
  # primary / primary_port hold the replication target, in priority order:
  #   1. the (host, port) pair a Sentinel reports — used VERBATIM, without any
  #      role re-verification and without mapping it back to a pod FQDN (redis
  #      addon parity: in NodePort mode the pair is node_ip + the pod's unique
  #      NodePort, which is directly routable).
  #   2. the lowest-ordinal pod of the component, when no Sentinel answers
  #      (fresh bootstrap, full-cluster restart, or Sentinel still starting).
  primary=""
  primary_port="${service_port}"

  if ! is_empty "${SENTINEL_COMPONENT_NAME}" && ! is_empty "${SENTINEL_POD_FQDN_LIST}"; then
    # Ask every Sentinel and adopt the address most of them report.  Retry 3
    # times (3s apart) so a still-converging fleet gets a chance before falling
    # back to the ordinal election.
    local attempt
    for attempt in $(seq 1 3); do
      if get_primary_addr_from_sentinels; then
        echo "INFO: using Sentinel-reported master ${primary}:${primary_port} as-is (attempt ${attempt}/3)." >&2
        break
      fi
      echo "INFO: no Sentinel-reported master yet (attempt ${attempt}/3) — retrying in 3s." >&2
      if [ "${attempt}" -lt 3 ]; then
        sleep_when_ut_mode_false 3
      fi
    done
  fi

  if is_empty "${primary}"; then
    # No Sentinel answer (or no Sentinel component at all): the lowest-ordinal
    # pod is the deterministic primary — the same rule the initial bootstrap
    # and the data-side registration use.
    primary=$(elect_lexicographic_primary)
    primary_port="${service_port}"
    echo "INFO: no Sentinel-reported master — electing the lowest-ordinal pod ${primary}." >&2
  fi

  if is_empty "${primary}"; then
    echo "ERROR: could not determine the primary — aborting." >&2
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
  # Two rules (redis parity): a pod-FQDN report contains "<pod>.<component>",
  # and an address report (NodePort / LoadBalancer) equals this pod's own
  # replica-announce pair.
  if check_current_pod_is_primary; then
    echo "INFO: this pod is the primary — no replicaof directive needed." >&2
    return
  fi

  echo "replicaof ${primary} ${primary_port}" >> "${CONF_RUNTIME}"
}

# get_primary_addr_from_sentinels — ask every Sentinel for the master address and
# adopt the (host, port) pair most of them report, exactly as the data pod
# announced it (pod FQDN, or node_ip:NodePort / LB host:port in NodePort /
# LoadBalancer mode).  Fills the globals primary / primary_port.
#
# Same shape as the redis addon: the announced pair is used verbatim as the
# replicaof target — a Sentinel never reports a pod FQDN in NodePort mode (it
# holds the NODE ip + the pod's unique NodePort), so mapping the address back to
# a pod FQDN is neither needed nor reliable.  The address is trusted as-is: no
# role re-verification, the pair with the most votes wins even while the fleet
# is still converging.  Returns 1 only when no Sentinel answered.
get_primary_addr_from_sentinels() {
  local sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"
  local master_name="${VALKEY_COMPONENT_NAME}"

  # shellcheck disable=SC2206
  local sentinel_cli_base=(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -p "${sentinel_port}")
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    sentinel_cli_base+=(-a "${SENTINEL_PASSWORD}")
  fi

  local -a sentinel_fqdns=()
  IFS=',' read -ra sentinel_fqdns <<< "${SENTINEL_POD_FQDN_LIST}"
  local total="${#sentinel_fqdns[@]}"

  local -A addr_count=()
  local s_fqdn response host port key
  for s_fqdn in "${sentinel_fqdns[@]}"; do
    [ -n "${s_fqdn}" ] || continue
    response=$(timeout 3 "${sentinel_cli_base[@]}" -h "${s_fqdn}" \
                 SENTINEL get-master-addr-by-name "${master_name}" 2>/dev/null) || continue
    # The reply is two lines: <host> and <port>.
    host=$(printf '%s' "${response}" | sed -n '1p' | tr -d '\r\n')
    port=$(printf '%s' "${response}" | sed -n '2p' | tr -d '\r\n')
    [ -n "${host}" ] || continue
    [ "${host}" = "(nil)" ] && continue
    [ -n "${port}" ] || continue

    key="${host}:${port}"
    addr_count["${key}"]=$(( ${addr_count["${key}"]:-0} + 1 ))
    echo "INFO: sentinel ${s_fqdn} reports master ${key}." >&2
  done

  local best_key="" best_count=0
  for key in "${!addr_count[@]}"; do
    if [ "${addr_count[$key]}" -gt "${best_count}" ]; then
      best_key="${key}"
      best_count="${addr_count[$key]}"
    fi
  done

  if [ -z "${best_key}" ]; then
    echo "INFO: no Sentinel reported a master address." >&2
    return 1
  fi

  primary="${best_key%%:*}"
  primary_port="${best_key##*:}"
  echo "INFO: ${best_count}/${total} Sentinels report master ${primary}:${primary_port} — taking it as-is." >&2
  return 0
}

# check_current_pod_is_primary — true when this pod is the master a Sentinel
# reported.  Two rules, both from the redis addon:
#   1. FQDN announce: the reported host contains "<pod-name>.<component-name>".
#   2. Address announce (NodePort / LoadBalancer): the reported (host, port)
#      equals this pod's own replica-announce pair.
check_current_pod_is_primary() {
  local pod_fqdn_prefix="${CURRENT_POD_NAME}.${VALKEY_COMPONENT_NAME}"
  if contains "${primary}" "${pod_fqdn_prefix}"; then
    echo "INFO: current pod is primary by name mapping (${primary})." >&2
    return 0
  fi
  if ! is_empty "${valkey_announce_host_value}" && ! is_empty "${valkey_announce_port_value}"; then
    if [ "${primary}" = "${valkey_announce_host_value}" ] && \
       [ "${primary_port}" = "${valkey_announce_port_value}" ]; then
      echo "INFO: current pod is primary by advertised mapping (${primary}:${primary_port})." >&2
      return 0
    fi
  fi
  return 1
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

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library
build_valkey_conf
start_valkey_server
