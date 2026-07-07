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

qdrant_bootstrap_service_available() {
  bootstrap_service_http_uri="$1"
  qdrant_curl -sf --max-time "${QDRANT_BOOTSTRAP_SERVICE_CHECK_TIMEOUT:-3}" \
    "${bootstrap_service_http_uri}/cluster" >/dev/null 2>&1
}

qdrant_start_mode() {
  bootstrap_service_http_uri="$1"

  if qdrant_has_existing_raft_state; then
    echo "restart"
    return 0
  fi

  if qdrant_bootstrap_service_available "$bootstrap_service_http_uri"; then
    echo "join"
    return 0
  fi

  if qdrant_should_self_bootstrap; then
    echo "bootstrap"
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
