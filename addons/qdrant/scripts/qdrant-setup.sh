#!/usr/bin/env bash

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="${QDRANT_COMMON_FILE:-/qdrant/scripts/common.sh}"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

qdrant_claim_initial_bootstrap() {
  qdrant_pod_uid="${CURRENT_POD_UID:-}"
  if [ -z "$qdrant_pod_uid" ]; then
    echo "ERROR: CURRENT_POD_UID is required to claim initial Qdrant bootstrap ownership." >&2
    return 1
  fi

  qdrant_storage_path="${QDRANT_STORAGE_PATH:-/qdrant/storage}"
  qdrant_existing_entry="$(find "$qdrant_storage_path" -mindepth 1 -maxdepth 1 ! -name lost+found -print -quit 2>/dev/null || true)"
  if [ -n "$qdrant_existing_entry" ]; then
    echo "INFO: Qdrant storage is not empty; waiting to join the existing cluster." >&2
    return 1
  fi

  return 0
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

  if qdrant_bootstrap_service_available "$bootstrap_service_http_uri"; then
    echo "join"
    return 0
  fi

  if qdrant_should_self_bootstrap; then
    if qdrant_existing_bootstrap_service_observed "$bootstrap_service_http_uri"; then
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

  cp tools/jq /bin/
  cp tools/curl /bin/

  load_common_library
  qdrant_set_tls_variables

  current_pod_fqdn="$(qdrant_current_pod_fqdn)"
  bootstrap_service_host="$(qdrant_bootstrap_service_host)"
  bootstrap_service_http_uri="${SCHEME}://${bootstrap_service_host}:6333"
  bootstrap_service_p2p_uri="${SCHEME}://${bootstrap_service_host}:6335"

  QDRANT_CURL_BIN="${QDRANT_CURL_BIN:-./tools/curl}"
  export QDRANT_CURL_BIN

  start_mode="$(qdrant_start_mode "$bootstrap_service_http_uri")"
  echo "INFO: Qdrant start mode: ${start_mode:-unknown}" >&2
  case "${start_mode}" in
    bootstrap)
      exec ./qdrant --uri "${SCHEME}://${current_pod_fqdn}:6335"
      ;;
    join)
      echo "JOIN EXISTING CLUSTER: ${bootstrap_service_host}"
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
