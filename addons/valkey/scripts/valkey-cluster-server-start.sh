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
#   VALKEY_DATA_DIR               persistent data directory (KB var)
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
  local missing="" canonical_data_dir
  [ -z "${CURRENT_POD_NAME:-}" ] && missing="${missing} CURRENT_POD_NAME"
  [ -z "${CURRENT_POD_IP:-}" ] && missing="${missing} CURRENT_POD_IP"
  [ -z "${CURRENT_SHARD_POD_FQDN_LIST:-}" ] && missing="${missing} CURRENT_SHARD_POD_FQDN_LIST"
  [ -z "${SERVICE_PORT:-}" ] && missing="${missing} SERVICE_PORT"
  [ -z "${VALKEY_DATA_DIR:-}" ] && missing="${missing} VALKEY_DATA_DIR"
  if [ -n "${missing}" ]; then
    echo "ERROR: valkey-cluster-server-start.sh missing required env:${missing} — refusing to start in cluster mode." >&2
    return 1
  fi
  case "${VALKEY_DATA_DIR}" in
    /*) [ "${VALKEY_DATA_DIR}" != "/" ] || {
      echo "ERROR: VALKEY_DATA_DIR must not be the filesystem root." >&2
      return 1
    } ;;
    *) echo "ERROR: VALKEY_DATA_DIR must be an absolute path." >&2; return 1 ;;
  esac
  canonical_data_dir=$(cd -P "${VALKEY_DATA_DIR}" 2>/dev/null && pwd -P) || {
    echo "ERROR: VALKEY_DATA_DIR must name an existing directory." >&2
    return 1
  }
  [ "${canonical_data_dir}" = "${VALKEY_DATA_DIR}" ] || {
    echo "ERROR: VALKEY_DATA_DIR must be a canonical path without symlinks or dot segments." >&2
    return 1
  }
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

offline_restore_marker_content() {
  printf 'rdb_sha256=%s\nmeta_sha256=%s\npod=%s' "${1}" "${2}" "${CURRENT_POD_NAME}"
}

cluster_restore_state_content() {
  printf 'phase=%s\nmeta_sha256=%s' "${1}" "${2}"
}

offline_restored_aof_is_pristine() {
  local expected_rdb_sha256="${1}" append_dirname append_filename append_dir base incr manifest
  local expected_manifest actual_manifest unexpected base_sha256
  append_dirname="${VALKEY_APPEND_DIRNAME-appendonlydir}"
  append_filename="${VALKEY_APPEND_FILENAME-appendonly.aof}"
  case "${append_dirname}" in
    ''|*/*|.|..)
      echo "ERROR: unsafe restored replica AOF path contract." >&2
      return 1 ;;
  esac
  case "${append_filename}" in
    ''|*/*|.|..)
      echo "ERROR: unsafe restored replica AOF path contract." >&2
      return 1 ;;
  esac
  append_dir="${VALKEY_DATA_DIR}/${append_dirname}"
  base="${append_dir}/${append_filename}.1.base.rdb"
  incr="${append_dir}/${append_filename}.1.incr.aof"
  manifest="${append_dir}/${append_filename}.manifest"
  [ -d "${append_dir}" ] && [ ! -L "${append_dir}" ] || return 1
  [ -f "${base}" ] && [ ! -L "${base}" ] && \
    [ -f "${incr}" ] && [ ! -L "${incr}" ] && \
    [ -f "${manifest}" ] && [ ! -L "${manifest}" ] || return 1
  [ ! -s "${incr}" ] || return 1
  base_sha256=$(sha256sum "${base}" 2>/dev/null | awk '{print $1}')
  [ "${base_sha256}" = "${expected_rdb_sha256}" ] || return 1
  expected_manifest=$(printf 'file %s seq 1 type b\nfile %s seq 1 type i' \
    "$(basename "${base}")" "$(basename "${incr}")")
  actual_manifest=$(cat "${manifest}" 2>/dev/null) || return 1
  [ "${actual_manifest}" = "${expected_manifest}" ] || return 1
  unexpected=$(find "${append_dir}" -mindepth 1 -maxdepth 1 \
    ! -name "$(basename "${base}")" \
    ! -name "$(basename "${incr}")" \
    ! -name "$(basename "${manifest}")" -print) || return 1
  [ -z "${unexpected}" ]
}

# Restore jobs populate the same per-shard archive onto every PVC. A non-first
# pod must discard that redundant copy before valkey-server starts, while no
# client can race the cleanup. The two-stage marker makes crashes before/after
# deletion distinguishable and prevents a later restart from clearing data
# that has already been replicated into this pod.
prepare_restored_replica_offline() {
  local meta="${VALKEY_DATA_DIR}/cluster-meta" first digest_count rdb_sha256 actual_rdb_sha256
  local prepare_marker prepared_marker expected actual tmp append_dirname meta_sha256
  local restore_state="${VALKEY_DATA_DIR}/.kb-cluster-restore-state"
  local state_phase state_meta_sha256 state_lines
  if [ -L "${meta}" ]; then
    echo "ERROR: cluster-meta is not a safe regular file." >&2
    return 1
  fi
  if [ ! -f "${meta}" ]; then
    if [ -e "${restore_state}" ] || [ -L "${restore_state}" ]; then
      [ -f "${restore_state}" ] && [ ! -L "${restore_state}" ] || {
        echo "ERROR: cluster restore state is not a safe regular file." >&2
        return 1
      }
      actual=$(cat "${restore_state}" 2>/dev/null) || return 1
      state_lines=$(printf '%s\n' "${actual}" | awk 'NF {n++} END {print n+0}')
      state_phase=$(printf '%s\n' "${actual}" | sed -n '1s/^phase=//p')
      state_meta_sha256=$(printf '%s\n' "${actual}" | sed -n '2s/^meta_sha256=//p')
      case "${state_meta_sha256}" in ''|*[!0-9a-fA-F]*) state_meta_sha256="" ;; esac
      if [ "${state_lines}" -eq 2 ] && [ "${state_phase}" = "formed" ] && [ "${#state_meta_sha256}" -eq 64 ]; then
        return 0
      fi
      echo "ERROR: prepared cluster restore state lacks cluster-meta; refusing ordinary startup." >&2
      return 1
    fi
    if [ -e "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare" ] || \
       [ -e "${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared" ]; then
      echo "ERROR: offline restore marker lacks cluster-meta; refusing ordinary startup." >&2
      return 1
    fi
    return 0
  fi
  meta_sha256=$(sha256sum "${meta}" 2>/dev/null | awk '{print $1}')
  [ "${#meta_sha256}" -eq 64 ] || { echo "ERROR: cannot identify restored replica cluster-meta." >&2; return 1; }
  [ -f "${restore_state}" ] && [ ! -L "${restore_state}" ] || {
    echo "ERROR: cluster-meta lacks its exact restore-state contract." >&2
    return 1
  }
  actual=$(cat "${restore_state}" 2>/dev/null) || return 1
  if [ "${actual}" = "$(cluster_restore_state_content formed "${meta_sha256}")" ]; then
    return 0
  fi
  [ "${actual}" = "$(cluster_restore_state_content prepared "${meta_sha256}")" ] || {
    echo "ERROR: cluster restore state does not match cluster-meta." >&2
    return 1
  }

  digest_count=$(grep -c '^rdb_sha256=' "${meta}" || true)
  [ "${digest_count}" -eq 1 ] || { echo "ERROR: restored replica cluster-meta requires exactly one rdb_sha256." >&2; return 1; }
  rdb_sha256=$(grep '^rdb_sha256=' "${meta}" | cut -d= -f2-)
  case "${rdb_sha256}" in ''|*[!0-9a-fA-F]*) echo "ERROR: invalid restored replica rdb_sha256." >&2; return 1 ;; esac
  [ "${#rdb_sha256}" -eq 64 ] || { echo "ERROR: invalid restored replica rdb_sha256 length." >&2; return 1; }
  first=$(printf '%s\n' "${CURRENT_SHARD_POD_FQDN_LIST}" | tr ',' '\n' | grep -v '^$' | LC_ALL=C sort | head -1)
  [ -n "${first}" ] || { echo "ERROR: restored shard roster has no first pod." >&2; return 1; }
  [ "${first%%.*}" != "${CURRENT_POD_NAME}" ] || return 0

  prepare_marker="${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepare"
  prepared_marker="${VALKEY_DATA_DIR}/.kb-restored-replica-offline-prepared"
  append_dirname="${VALKEY_APPEND_DIRNAME-appendonlydir}"
  case "${append_dirname}" in
    ''|*/*|.|..)
      echo "ERROR: unsafe restored replica AOF directory name '${append_dirname}'." >&2
      return 1 ;;
  esac
  expected=$(offline_restore_marker_content "${rdb_sha256}" "${meta_sha256}")
  if [ -e "${prepared_marker}" ] || [ -L "${prepared_marker}" ]; then
    [ -f "${prepared_marker}" ] && [ ! -L "${prepared_marker}" ] || {
      echo "ERROR: offline prepared marker is not a safe regular file." >&2
      return 1
    }
    actual=$(cat "${prepared_marker}" 2>/dev/null) || return 1
    [ "${actual}" = "${expected}" ] || { echo "ERROR: offline prepared marker does not match this restore target." >&2; return 1; }
    if [ -e "${prepare_marker}" ] || [ -L "${prepare_marker}" ]; then
      [ -f "${prepare_marker}" ] && [ ! -L "${prepare_marker}" ] || {
        echo "ERROR: offline prepare marker is not a safe regular file." >&2
        return 1
      }
      actual=$(cat "${prepare_marker}" 2>/dev/null) || return 1
      [ "${actual}" = "${expected}" ] || { echo "ERROR: offline prepare marker does not match this restore target." >&2; return 1; }
    fi
    return 0
  fi

  if [ -e "${prepare_marker}" ] || [ -L "${prepare_marker}" ]; then
    [ -f "${prepare_marker}" ] && [ ! -L "${prepare_marker}" ] || {
      echo "ERROR: offline prepare marker is not a safe regular file." >&2
      return 1
    }
    actual=$(cat "${prepare_marker}" 2>/dev/null) || return 1
    [ "${actual}" = "${expected}" ] || { echo "ERROR: offline prepare marker does not match this restore target." >&2; return 1; }
  else
    [ -f "${VALKEY_DATA_DIR}/dump.rdb" ] && [ ! -L "${VALKEY_DATA_DIR}/dump.rdb" ] || {
      echo "ERROR: restored replica dump.rdb is not a safe regular file." >&2
      return 1
    }
    actual_rdb_sha256=$(sha256sum "${VALKEY_DATA_DIR}/dump.rdb" 2>/dev/null | awk '{print $1}')
    [ "${actual_rdb_sha256}" = "${rdb_sha256}" ] || { echo "ERROR: restored replica dump.rdb does not match cluster-meta." >&2; return 1; }
    offline_restored_aof_is_pristine "${rdb_sha256}" || { echo "ERROR: restored replica multipart AOF is not the pristine restore seed." >&2; return 1; }
    tmp=$(mktemp "${prepare_marker}.tmp.XXXXXX") || {
      echo "ERROR: cannot allocate offline restore prepare marker." >&2
      return 1
    }
    printf '%s\n' "${expected}" > "${tmp}" && mv -f "${tmp}" "${prepare_marker}" && sync || {
      rm -f "${tmp}"
      echo "ERROR: cannot persist offline restore prepare marker." >&2
      return 1
    }
  fi

  rm -f "${VALKEY_DATA_DIR}/dump.rdb"
  rm -rf "${VALKEY_DATA_DIR:?}/${append_dirname}"
  sync
  [ ! -e "${VALKEY_DATA_DIR}/dump.rdb" ] && [ ! -e "${VALKEY_DATA_DIR}/${append_dirname}" ] || {
    echo "ERROR: restored replica payload remains after offline preparation." >&2
    return 1
  }
  tmp=$(mktemp "${prepared_marker}.tmp.XXXXXX") || {
    echo "ERROR: cannot allocate offline restore prepared marker." >&2
    return 1
  }
  printf '%s\n' "${expected}" > "${tmp}" && mv -f "${tmp}" "${prepared_marker}" && sync || {
    rm -f "${tmp}"
    echo "ERROR: cannot persist offline restore prepared marker." >&2
    return 1
  }
  rm -f "${prepare_marker}"
  echo "Prepared restored replica ${CURRENT_POD_NAME} offline before valkey-server start."
}

build_cluster_conf() {
  # conf dir overridable so the contract spec exercises THIS function, not
  # an inline copy (fresh-eyes review: a re-implemented sandbox guarded
  # nothing — the announce trio could be deleted here and specs still passed).
  local conf_dir="${VALKEY_CONF_DIR:-/etc/valkey}"
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
  local acl_file="${VALKEY_ACL_FILE:-/data/users.acl}"
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
prepare_restored_replica_offline || exit 1
conf_file=$(build_cluster_conf "${self_fqdn}")
start_cluster_server "${conf_file}"
