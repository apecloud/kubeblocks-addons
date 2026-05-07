#!/bin/bash
# valkey-sentinel-start.sh — builds sentinel.conf and starts valkey-server --sentinel.
#
# Sentinel state is stored in /data/sentinel/redis-sentinel.conf (on PVC).
# On first boot the file does not exist — we create a minimal one.
# On subsequent boots the file already contains the current master address
# (rewritten by Valkey after each failover), so we only patch the dynamic
# parts (announce addr, port, ACL, TLS) without overwriting the monitor stanza.

set -e

SENTINEL_CONF_DIR="/data/sentinel"
SENTINEL_CONF="${SENTINEL_CONF_DIR}/redis-sentinel.conf"
SENTINEL_ACL="/data/users.acl"
sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

rebuild_sentinel_acl() {
  local acl_tmp="${SENTINEL_ACL}.tmp"
  # Preserve non-default-user lines, then atomically replace the file.
  # Using a temp file + mv avoids a crash window where the default user
  # line is deleted but the new one has not yet been appended.
  if [ -f "${SENTINEL_ACL}" ]; then
    grep -v "^user default on" "${SENTINEL_ACL}" > "${acl_tmp}" || true
  else
    : > "${acl_tmp}"
  fi
  unset_xtrace_when_ut_mode_false
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    local sha256
    sha256=$(echo -n "${SENTINEL_PASSWORD}" | sha256sum | cut -d' ' -f1)
    echo "user default on #${sha256} ~* &* +@all" >> "${acl_tmp}"
  else
    echo "user default on nopass ~* &* +@all" >> "${acl_tmp}"
  fi
  set_xtrace_when_ut_mode_false
  mv "${acl_tmp}" "${SENTINEL_ACL}"
}

# Strip dynamic fields that must be re-computed on every start, leaving
# the sentinel monitor / known-replica stanzas (written by Valkey) intact.
reset_dynamic_conf() {
  mkdir -p "${SENTINEL_CONF_DIR}"
  if [ -f "${SENTINEL_CONF}" ]; then
    sed -i \
      -e "/^sentinel announce-ip/d" \
      -e "/^sentinel announce-port/d" \
      -e "/^sentinel resolve-hostnames/d" \
      -e "/^sentinel announce-hostnames/d" \
      -e "/^port /d" \
      -e "/^tls-port /d" \
      -e "/^tls-cert-file/d" \
      -e "/^tls-key-file/d" \
      -e "/^tls-ca-cert-file/d" \
      -e "/^tls-auth-clients/d" \
      -e "/^tls-replication/d" \
      -e "/^aclfile/d" \
      -e "/^user default on/d" \
      "${SENTINEL_CONF}"
    # Always strip auth lines so stale credentials are not left behind
    # if the password is removed between restarts (auth → no-auth transition).
    sed -i \
      -e "/^sentinel sentinel-user/d" \
      -e "/^sentinel sentinel-pass/d" \
      "${SENTINEL_CONF}"
  fi
}

append_dynamic_conf() {
  # Announce address — prefer NodePort, fall back to FQDN.
  local announce_host="" announce_port=""
  if ! is_empty "${REDIS_SENTINEL_ADVERTISED_PORT}"; then
    local pod_ordinal
    pod_ordinal=$(extract_obj_ordinal "${CURRENT_POD_NAME}")
    for entry in $(echo "${REDIS_SENTINEL_ADVERTISED_PORT}" | tr ',' '\n'); do
      local svc_name svc_port
      svc_name="${entry%%:*}"; svc_port="${entry##*:}"
      if [ "$(extract_obj_ordinal "${svc_name}")" = "${pod_ordinal}" ]; then
        announce_host="${CURRENT_POD_HOST_IP}"
        announce_port="${svc_port}"
        break
      fi
    done
  fi
  if is_empty "${announce_host}"; then
    local my_fqdn
    my_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars \
                "${SENTINEL_POD_FQDN_LIST}" "${CURRENT_POD_NAME}")
    if is_empty "${my_fqdn}"; then
      echo "ERROR: cannot resolve FQDN for ${CURRENT_POD_NAME}" >&2
      exit 1
    fi
    # FQDN-based announce — Sentinel resolves hostnames
    {
      echo "sentinel announce-ip ${my_fqdn}"
      echo "sentinel resolve-hostnames yes"
      echo "sentinel announce-hostnames yes"
    } >> "${SENTINEL_CONF}"
  else
    {
      echo "sentinel announce-ip ${announce_host}"
      echo "sentinel announce-port ${announce_port}"
    } >> "${SENTINEL_CONF}"
  fi

  # Port
  if [ "${TLS_ENABLED}" = "true" ]; then
    {
      echo "port 0"
      echo "tls-port ${sentinel_port}"
      echo "tls-cert-file ${TLS_MOUNT_PATH}/tls.crt"
      echo "tls-key-file ${TLS_MOUNT_PATH}/tls.key"
      echo "tls-ca-cert-file ${TLS_MOUNT_PATH}/ca.crt"
      echo "tls-auth-clients no"
      echo "tls-replication yes"
    } >> "${SENTINEL_CONF}"
  else
    echo "port ${sentinel_port}" >> "${SENTINEL_CONF}"
  fi

  # Auth
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    {
      echo "sentinel sentinel-user ${SENTINEL_USER:-default}"
      echo "sentinel sentinel-pass ${SENTINEL_PASSWORD}"
    } >> "${SENTINEL_CONF}"
  fi
  echo "aclfile ${SENTINEL_ACL}" >> "${SENTINEL_CONF}"
}

create_initial_conf_if_needed() {
  if [ ! -f "${SENTINEL_CONF}" ]; then
    echo "First boot — creating empty sentinel conf."
    mkdir -p "${SENTINEL_CONF_DIR}"
    touch "${SENTINEL_CONF}"
  fi
}

# _find_master_fqdn — scan all data pod FQDNs and return the master's FQDN via stdout.
# Returns empty string if none found.
_find_master_fqdn() {
  local data_port="${SERVICE_PORT:-6379}"
  local tls_args=""
  [ "${TLS_ENABLED}" = "true" ] && tls_args="--tls --insecure"
  for fqdn in $(echo "${VALKEY_POD_FQDN_LIST:-}" | tr ',' '\n'); do
    [ -z "${fqdn}" ] && continue
    local role
    if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
      # shellcheck disable=SC2086
      role=$(valkey-cli -h "${fqdn}" -p "${data_port}" \
        ${tls_args} \
        -a "${VALKEY_DEFAULT_PASSWORD}" --no-auth-warning \
        info replication 2>/dev/null | grep "^role:" | tr -d '\r\n' | cut -d: -f2)
    else
      # shellcheck disable=SC2086
      role=$(valkey-cli -h "${fqdn}" -p "${data_port}" \
        ${tls_args} \
        info replication 2>/dev/null | grep "^role:" | tr -d '\r\n' | cut -d: -f2)
    fi
    if [ "${role}" = "master" ]; then
      echo "${fqdn}"
      return 0
    fi
  done
}

# _sentinel_cli — run a valkey-cli command against this sentinel's own port.
_sentinel_cli() {
  local cmd="valkey-cli -h 127.0.0.1 -p ${sentinel_port} --no-auth-warning"
  if [ "${TLS_ENABLED}" = "true" ]; then
    cmd="${cmd} --tls --insecure"
  fi
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    cmd="${cmd} -a ${SENTINEL_PASSWORD}"
  fi
  ${cmd} "$@" 2>/dev/null
}

# _register_monitor — dynamically register the master with the running sentinel
# via SENTINEL MONITOR + SENTINEL SET auth-pass.
_register_monitor() {
  local master_fqdn="${1}"
  local data_port="${SERVICE_PORT:-6379}"
  local monitor_name="${VALKEY_COMPONENT_NAME}"
  if is_empty "${monitor_name}"; then
    echo "ERROR: VALKEY_COMPONENT_NAME is not set — cannot register sentinel monitor." >&2
    return 1
  fi
  echo "INFO: registering master ${master_fqdn}:${data_port} with sentinel as '${monitor_name}'." >&2
  _sentinel_cli SENTINEL MONITOR "${monitor_name}" "${master_fqdn}" "${data_port}" 2
  if ! is_empty "${VALKEY_DEFAULT_PASSWORD}"; then
    _sentinel_cli SENTINEL SET "${monitor_name}" auth-pass "${VALKEY_DEFAULT_PASSWORD}"
  fi
}

# _wait_sentinel_ready — block until this sentinel's own 26379 port responds to PING.
_wait_sentinel_ready() {
  until _sentinel_cli PING | grep -q PONG; do
    sleep 1
  done
}

# _background_monitor_discovery — runs in background after sentinel starts.
# Polls until sentinel is monitoring at least one master (either discovered
# itself or learned from peer sentinels via pub/sub). If still 0 masters,
# probes data pods for a master and registers it dynamically.
# Loops indefinitely — no timeout — so even a very slow primary restart works.
_background_monitor_discovery() {
  _wait_sentinel_ready

  while true; do
    # If sentinel already knows a master (learned from peers or previous run), done.
    local masters
    masters=$(_sentinel_cli INFO sentinel | grep "^sentinel_masters:" | tr -d '\r\n' | cut -d: -f2)
    if [ "${masters:-0}" -ge 1 ]; then
      echo "INFO: sentinel is monitoring ${masters} master(s), background discovery done." >&2
      return 0
    fi

    # Try to find the master from data pods and register.
    local master_fqdn
    master_fqdn=$(_find_master_fqdn)
    if [ -n "${master_fqdn}" ]; then
      _register_monitor "${master_fqdn}"
      # Verify registration succeeded — SENTINEL MONITOR can fail transiently
      # (e.g. DNS not yet ready) and return ERR without exiting non-zero.
      sleep 2
      masters=$(_sentinel_cli INFO sentinel | grep "^sentinel_masters:" | tr -d '\r\n' | cut -d: -f2)
      if [ "${masters:-0}" -ge 1 ]; then
        echo "INFO: sentinel is monitoring ${masters} master(s), background discovery done." >&2
        return 0
      fi
      echo "WARNING: SENTINEL MONITOR registration failed, will retry in 5s..." >&2
    else
      echo "INFO: master not yet available, retrying in 5s..." >&2
    fi

    sleep 5
  done
}

# ── main ────────────────────────────────────────────────────────────────
load_common_library
create_initial_conf_if_needed
rebuild_sentinel_acl
reset_dynamic_conf
append_dynamic_conf

# If the conf has no monitor stanza, start a background loop that will
# discover the master and register it once sentinel and data pods are ready.
# This handles simultaneous restarts where the primary may not be up yet.
if ! grep -q "^sentinel monitor" "${SENTINEL_CONF}" 2>/dev/null; then
  echo "INFO: no sentinel monitor stanza — starting background discovery loop." >&2
  _background_monitor_discovery &
fi

echo "Starting: valkey-server ${SENTINEL_CONF} --sentinel"
exec valkey-server "${SENTINEL_CONF}" --sentinel
