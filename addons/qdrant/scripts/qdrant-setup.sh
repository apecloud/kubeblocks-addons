#!/usr/bin/env bash

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="${QDRANT_COMMON_FILE:-/qdrant/scripts/common.sh}"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

configure_tls() {
  SCHEME="http"
  CURL_TLS=""
  if [ "${TLS_ENABLED:-}" = "true" ]; then
    SCHEME="https"
    CURL_TLS="-k"
  fi
}

wait_for_bootstrap_service() {
  bootstrap_service_http_uri="$1"
  until qdrant_curl -sf --max-time 10 "${bootstrap_service_http_uri}/cluster" >/dev/null; do
    echo "INFO: wait for bootstrap node starting..."
    sleep 10;
  done
}

qdrant_has_existing_raft_state() {
  qdrant_storage_path="${QDRANT_STORAGE_PATH:-/qdrant/storage}"
  [ -s "${qdrant_storage_path}/raft_state.json" ]
}

qdrant_bootstrap_owner_file() {
  qdrant_storage_path="${QDRANT_STORAGE_PATH:-/qdrant/storage}"
  printf "%s" "${QDRANT_BOOTSTRAP_OWNER_FILE:-${qdrant_storage_path}/.kubeblocks-bootstrap-owner}"
}

qdrant_record_existing_cluster() {
  qdrant_owner_file="$(qdrant_bootstrap_owner_file)"
  qdrant_owner_tmp="${qdrant_owner_file}.tmp.$$"

  if ! (umask 077 && printf '%s\n' "existing-cluster" > "$qdrant_owner_tmp" && mv -f "$qdrant_owner_tmp" "$qdrant_owner_file"); then
    rm -f "$qdrant_owner_tmp"
    echo "ERROR: cannot persist the existing-cluster bootstrap marker at ${qdrant_owner_file}." >&2
    return 1
  fi
}

qdrant_claim_initial_bootstrap() {
  qdrant_pod_uid="${CURRENT_POD_UID:-}"
  if [ -z "$qdrant_pod_uid" ]; then
    echo "ERROR: CURRENT_POD_UID is required to claim initial Qdrant bootstrap ownership." >&2
    return 1
  fi

  qdrant_owner_file="$(qdrant_bootstrap_owner_file)"
  if [ -e "$qdrant_owner_file" ]; then
    qdrant_bootstrap_owner="$(cat "$qdrant_owner_file" 2>/dev/null || true)"
    echo "INFO: initial bootstrap was already claimed by ${qdrant_bootstrap_owner:-an unknown pod}; pod UID ${qdrant_pod_uid} will wait to join." >&2
    return 1
  fi

  qdrant_storage_path="${QDRANT_STORAGE_PATH:-/qdrant/storage}"
  qdrant_existing_entry="$(find "$qdrant_storage_path" -mindepth 1 -maxdepth 1 ! -name lost+found -print -quit 2>/dev/null || true)"
  if [ -n "$qdrant_existing_entry" ]; then
    echo "INFO: bootstrap marker is absent but Qdrant storage is not empty; waiting to join the existing cluster." >&2
    return 1
  fi

  if (set -o noclobber; umask 077; printf 'bootstrap-attempt:%s\n' "$qdrant_pod_uid" > "$qdrant_owner_file") 2>/dev/null; then
    return 0
  fi

  if [ ! -e "$qdrant_owner_file" ]; then
    echo "ERROR: cannot persist the initial bootstrap claim at ${qdrant_owner_file}." >&2
    return 1
  fi

  qdrant_bootstrap_owner="$(cat "$qdrant_owner_file" 2>/dev/null || true)"
  echo "INFO: initial bootstrap was concurrently claimed by ${qdrant_bootstrap_owner:-an unknown pod}; pod UID ${qdrant_pod_uid} will wait to join." >&2
  return 1
}

qdrant_bootstrap_service_available() {
  bootstrap_service_http_uri="$1"
  qdrant_curl -sf --max-time "${QDRANT_BOOTSTRAP_SERVICE_CHECK_TIMEOUT:-3}" \
    "${bootstrap_service_http_uri}/cluster" >/dev/null 2>&1
}

qdrant_existing_bootstrap_service_observed() {
  bootstrap_service_http_uri="$1"
  bootstrap_discovery_attempts="${QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_ATTEMPTS:-10}"
  bootstrap_discovery_sleep_seconds="${QDRANT_BOOTSTRAP_SERVICE_DISCOVERY_SLEEP_SECONDS:-3}"
  bootstrap_discovery_attempt=1

  while [ "$bootstrap_discovery_attempt" -le "$bootstrap_discovery_attempts" ]; do
    if qdrant_bootstrap_service_available "$bootstrap_service_http_uri"; then
      return 0
    fi

    if [ "$bootstrap_discovery_attempt" -lt "$bootstrap_discovery_attempts" ]; then
      echo "INFO: bootstrap service is not reachable yet; retrying before initial bootstrap decision (${bootstrap_discovery_attempt}/${bootstrap_discovery_attempts})" >&2
      sleep "$bootstrap_discovery_sleep_seconds"
    fi
    bootstrap_discovery_attempt=$((bootstrap_discovery_attempt + 1))
  done

  return 1
}

qdrant_start_mode() {
  bootstrap_service_http_uri="$1"

  if qdrant_has_existing_raft_state; then
    qdrant_record_existing_cluster || return 1
    echo "restart"
    return 0
  fi

  if qdrant_bootstrap_service_available "$bootstrap_service_http_uri"; then
    qdrant_record_existing_cluster || return 1
    echo "join"
    return 0
  fi

  if qdrant_should_self_bootstrap; then
    if qdrant_existing_bootstrap_service_observed "$bootstrap_service_http_uri"; then
      qdrant_record_existing_cluster || return 1
      echo "join"
      return 0
    fi
    if qdrant_claim_initial_bootstrap; then
      echo "bootstrap"
      return 0
    fi
    echo "join"
    return 0
  fi

  echo "join"
}

qdrant_setup_main() {
  set -o errexit
  set -o pipefail

  load_common_library
  configure_tls

  current_pod_fqdn="$(qdrant_current_pod_fqdn)"
  bootstrap_service_host="$(qdrant_bootstrap_service_host)"
  bootstrap_service_http_uri="${SCHEME}://${bootstrap_service_host}:6333"
  bootstrap_service_p2p_uri="${SCHEME}://${bootstrap_service_host}:6335"

  QDRANT_CURL_BIN="${QDRANT_CURL_BIN:-./tools/curl}"
  export QDRANT_CURL_BIN

  case "$(qdrant_start_mode "$bootstrap_service_http_uri")" in
    restart|bootstrap)
      exec ./qdrant --uri "${SCHEME}://${current_pod_fqdn}:6335"
      ;;
    join)
      echo "JOIN EXISTING CLUSTER: ${bootstrap_service_host}"
      wait_for_bootstrap_service "$bootstrap_service_http_uri"
      exec ./qdrant --bootstrap "$bootstrap_service_p2p_uri" --uri "${SCHEME}://${current_pod_fqdn}:6335"
      ;;
    *)
      echo "ERROR: unknown qdrant start mode" >&2
      return 1
      ;;
  esac
}

if [ "${QDRANT_SETUP_UNIT_TEST:-}" != "true" ]; then
  qdrant_setup_main "$@"
fi
