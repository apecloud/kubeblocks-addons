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


extract_lb_host_by_svc_name() {
  local svc_name="$1"
  for lb_composed_name in $(echo "$VALKEY_SENTINEL_LB_ADVERTISED_HOST" | tr ',' '\n' ); do
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
  if ! is_empty "${VALKEY_SENTINEL_ADVERTISED_PORT}"; then
    local pod_ordinal
    pod_ordinal=$(extract_obj_ordinal "${CURRENT_POD_NAME}")
    for entry in $(echo "${VALKEY_SENTINEL_ADVERTISED_PORT}" | tr ',' '\n'); do
      local svc_name svc_port
      svc_name="${entry%%:*}"; svc_port="${entry##*:}"
      if [ "$(extract_obj_ordinal "${svc_name}")" = "${pod_ordinal}" ]; then
        announce_port="${svc_port}"
        if [ -n "$lb_host" ]; then
          lb_host=$(extract_lb_host_by_svc_name "$svc_name")
          announce_host=$lb_host
          announce_port=26379
        else
          announce_host="${CURRENT_POD_HOST_IP}"
        fi
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


# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

# ── main ────────────────────────────────────────────────────────────────
load_common_library
create_initial_conf_if_needed
rebuild_sentinel_acl
reset_dynamic_conf
append_dynamic_conf

echo "Starting: valkey-server ${SENTINEL_CONF} --sentinel"
exec valkey-server "${SENTINEL_CONF}" --sentinel
