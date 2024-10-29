#!/usr/bin/env bash

set -o errexit
set -o nounset
set -o pipefail

# Constants
DEFAULT_TIMEOUT=3
DEFAULT_PROTOCOL="https"
ES_PORT=9200

log_failure() {
  local error_details=$1
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')

  local error_json="{\"timestamp\": \"${timestamp}\", \"message\": \"readiness probe failed\", ${error_details}}"
  echo "${error_json}" | tee /proc/1/fd/2 2> /dev/null
}

get_probe_password_path() {
  # Get probe password file path
  # Maintain backwards compatibility with 1.0.0.beta-1, prioritize PROBE_PASSWORD_PATH
  if [[ -z "${PROBE_PASSWORD_PATH:-}" ]]; then
    echo "${PROBE_PASSWORD_FILE:-}"
  else
    echo "${PROBE_PASSWORD_PATH}"
  fi
}

setup_auth() {
  # Setup basic authentication
  local password_path
  password_path=$(get_probe_password_path)

  if [[ -n "${PROBE_USERNAME:-}" ]] && [[ -f "${password_path}" ]]; then
    local password
    password=$(<"${password_path}")
    echo "-u ${PROBE_USERNAME}:${password}"
  else
    echo ""
  fi
}

get_loopback_address() {
  # Determine IPv4 or IPv6 loopback address based on POD_IP
  if [[ ${POD_IP:-} =~ .*:.* ]]; then
    echo "[::1]"
  else
    echo "127.0.0.1"
  fi
}

# request Elasticsearch on /
# we are turning globbing off to allow for unescaped [] in case of IPv6
check_elasticsearch() {
  local endpoint=$1
  local auth=$2
  local timeout=$3

  local status
  local curl_rc

  status=$(curl -o /dev/null \
                -w "%{http_code}" \
                --max-time "${timeout}" \
                -XGET \
                -g \
                -s \
                -k \
                ${auth} \
                "${endpoint}" \
          ) || curl_rc=$?

  if [[ ${curl_rc:-0} -ne 0 ]]; then
    log_failure "\"curl_rc\": \"${curl_rc}\""
    return 1
  fi

  if [[ ${status} != "200" ]]; then
    log_failure "\"status\": \"${status}\""
    return 1
  fi
}

readiness_probe() {
  # Get environment variables or use defaults
  local timeout="${READINESS_PROBE_TIMEOUT:-${DEFAULT_TIMEOUT}}"
  local protocol="${READINESS_PROBE_PROTOCOL:-${DEFAULT_PROTOCOL}}"

  # Setup authentication
  local auth
  auth=$(setup_auth)

  # Get loopback address
  local loopback
  loopback=$(get_loopback_address)

  # Build endpoint URL
  local endpoint="${protocol}://${loopback}:${ES_PORT}/"

  # Execute health check
  if ! check_elasticsearch "${endpoint}" "${auth}" "${timeout}"; then
    echo "readiness probe check failed" >&2
    exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
readiness_probe