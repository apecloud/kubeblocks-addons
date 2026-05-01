#!/bin/bash
# valkey-sentinel-ping.sh — liveness/readiness probe for the Sentinel container.
#
# Uses valkey-cli PING against the local Sentinel port.  A response of "PONG"
# means the Sentinel process is alive and accepting connections.

set -e
# shellcheck source=/dev/null
source /scripts/common.sh

sentinel_port="${SENTINEL_SERVICE_PORT:-26379}"

check_sentinel_ok() {
  local response
  if ! is_empty "${SENTINEL_PASSWORD}"; then
    response=$(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h localhost -p "${sentinel_port}" \
                 -a "${SENTINEL_PASSWORD}" PING 2>/dev/null)
  else
    response=$(valkey-cli --no-auth-warning ${VALKEY_CLI_TLS_ARGS} -h localhost -p "${sentinel_port}" \
                 PING 2>/dev/null)
  fi

  if [ "${response}" != "PONG" ]; then
    echo "Sentinel PING failed (got: '${response}')" >&2
    return 1
  fi
}

call_func_with_retry 3 3 check_sentinel_ok || exit 1
