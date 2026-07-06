#!/bin/bash
# valkey-cluster-server-start.sh — entrypoint for a Valkey Cluster (sharding)
# data pod.
#
# Scope (phase A): render runtime config and exec valkey-server with cluster
# mode enabled. Cluster formation (--cluster create), shard scale in/out and
# role management are separate lifecycle actions (phase B/C) — this script
# must NOT wait for the cluster to form; a node is allowed to start alone and
# be joined later.
#
# v1 boundary: in-cluster networking only. Announce addresses are the pod
# FQDN; NodePort/LB advertise is deliberately unsupported (see design record
# in issue #3021).
#
# Required env (fail fast when absent — no silent fallback):
#   CURRENT_POD_NAME              current pod name (KB var)
#   CURRENT_POD_IP                current pod IP (KB var)
#   CURRENT_SHARD_POD_FQDN_LIST   comma list of this shard's pod FQDNs (KB var)
#   SERVICE_PORT                  data port (KB var)
# Optional env:
#   CLUSTER_BUS_PORT              cluster bus port (default SERVICE_PORT+10000)
#   VALKEY_DEFAULT_PASSWORD       default-user password (requirepass + ACL)
#   VALKEY_CLI_TLS_ARGS           populated when TLS enabled (not used here,
#                                 present for parity with sentinel scripts)

# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

set -e

load_common_library() {
  # shellcheck source=/dev/null
  source /scripts/common.sh
}

# Fail-fast validation: cluster mode without its contract inputs must never
# limp along on defaults (design contract class 1/2 — no silent fallback).
validate_required_env() {
  local missing=""
  [ -z "${CURRENT_POD_NAME:-}" ] && missing="${missing} CURRENT_POD_NAME"
  [ -z "${CURRENT_POD_IP:-}" ] && missing="${missing} CURRENT_POD_IP"
  [ -z "${CURRENT_SHARD_POD_FQDN_LIST:-}" ] && missing="${missing} CURRENT_SHARD_POD_FQDN_LIST"
  [ -z "${SERVICE_PORT:-}" ] && missing="${missing} SERVICE_PORT"
  if [ -n "${missing}" ]; then
    echo "ERROR: valkey-cluster-server-start.sh missing required env:${missing} — refusing to start in cluster mode." >&2
    return 1
  fi
  validate_port_range SERVICE_PORT "${SERVICE_PORT}" || return 1
  if [ -n "${CLUSTER_BUS_PORT:-}" ]; then
    validate_port_range CLUSTER_BUS_PORT "${CLUSTER_BUS_PORT}" || return 1
  fi
  return 0
}

# A port must be an integer in 1..65535 — 0 and non-numeric are refused
# (review finding: 0 and garbage previously slipped through).
validate_port_range() {
  local name="$1" value="$2"
  case "${value}" in
    ''|*[!0-9]*)
      echo "ERROR: ${name} must be an integer in 1..65535, got '${value}'." >&2
      return 1 ;;
  esac
  if [ "${value}" -lt 1 ] || [ "${value}" -gt 65535 ]; then
    echo "ERROR: ${name} must be an integer in 1..65535, got '${value}'." >&2
    return 1
  fi
  return 0
}

# Resolve this pod's announce FQDN from the shard FQDN list (never derive it
# by string arithmetic on the pod name — use the KB-provided list).
resolve_self_fqdn() {
  local fqdn
  IFS=',' read -ra _shard_fqdns <<< "${CURRENT_SHARD_POD_FQDN_LIST}"
  for fqdn in "${_shard_fqdns[@]}"; do
    if [ "${fqdn%%.*}" = "${CURRENT_POD_NAME}" ]; then
      echo "${fqdn}"
      return 0
    fi
  done
  echo "ERROR: pod '${CURRENT_POD_NAME}' not found in CURRENT_SHARD_POD_FQDN_LIST='${CURRENT_SHARD_POD_FQDN_LIST}'." >&2
  return 1
}

build_cluster_conf() {
  local conf_dir="/etc/valkey"
  local conf_file="${conf_dir}/valkey.conf"
  local port="${SERVICE_PORT}"
  local bus_port="${CLUSTER_BUS_PORT:-$((SERVICE_PORT + 10000))}"
  local self_fqdn="$1"

  mkdir -p "${conf_dir}"
  {
    echo "include /etc/conf/valkey.conf"
    echo "port ${port}"
    echo "cluster-port ${bus_port}"
    # v1 in-cluster announce (same trio the engine documents for stable
    # hostname endpoints): IP for the bus transport, pod FQDN as the
    # preferred endpoint so peers survive pod IP changes across restarts.
    echo "cluster-announce-ip ${CURRENT_POD_IP}"
    echo "cluster-announce-hostname ${self_fqdn}"
    echo "cluster-preferred-endpoint-type hostname"
  } > "${conf_file}"

  if [ -n "${VALKEY_DEFAULT_PASSWORD:-}" ]; then
    build_acl_file "${conf_file}"
  else
    echo "protected-mode no" >> "${conf_file}"
  fi
  echo "${conf_file}"
}

# Same per-node ACL model as the sentinel-mode start script: the default
# user is materialized into a local aclfile (ACL is never replicated by the
# engine, so every node owns its own file).
build_acl_file() {
  local conf_file="$1"
  local acl_file="/data/users.acl"
  local sha256
  sha256=$(echo -n "${VALKEY_DEFAULT_PASSWORD}" | sha256sum | cut -d' ' -f1)
  if [ -f "${acl_file}" ]; then
    sed -i "/user default/d" "${acl_file}"
  else
    touch "${acl_file}"
  fi
  echo "user default on #${sha256} ~* &* +@all" >> "${acl_file}"
  {
    echo "aclfile ${acl_file}"
    echo "masteruser default"
    echo "masterauth ${VALKEY_DEFAULT_PASSWORD}"
  } >> "${conf_file}"
}

start_cluster_server() {
  local conf_file="$1"
  echo "Starting valkey-server in cluster mode (port=${SERVICE_PORT}, bus=${CLUSTER_BUS_PORT:-$((SERVICE_PORT + 10000))})."
  exec valkey-server "${conf_file}"
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

load_common_library
validate_required_env || exit 1
self_fqdn=$(resolve_self_fqdn) || exit 1
conf_file=$(build_cluster_conf "${self_fqdn}")
start_cluster_server "${conf_file}"
