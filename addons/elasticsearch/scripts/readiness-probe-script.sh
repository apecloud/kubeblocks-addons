#!/usr/bin/env bash

# fail should be called as a last resort to help the user to understand why the probe failed
function fail {
  timestamp=$(date --iso-8601=seconds)
  echo "{\"timestamp\": \"${timestamp}\", \"message\": \"readiness probe failed\", "$1"}" | tee /proc/1/fd/2 2> /dev/null
  exit 1
}

READINESS_PROBE_TIMEOUT=${READINESS_PROBE_TIMEOUT:=3}

if [ "${TLS_ENABLED}" == "true" ]; then
    READINESS_PROBE_PROTOCOL=https
else
    READINESS_PROBE_PROTOCOL=http
fi

# setup basic auth if credentials are available
if [ -n "${ELASTIC_USER_PASSWORD}" ]; then
  BASIC_AUTH="-u elastic:${ELASTIC_USER_PASSWORD}"
else
  BASIC_AUTH=''
fi

# Check if we are using IPv6
if [[ $POD_IP =~ .*:.* ]]; then
  LOOPBACK="[::1]"
else
  LOOPBACK=127.0.0.1
fi

STALE_EXCLUSION_MARKER="/tmp/stale-exclusion-cleanup.pending"

function try_readiness_cleanup_stale_exclusion() {
  if [ -z "${POD_NAME:-}" ]; then
    rm -f "${STALE_EXCLUSION_MARKER}"
    echo "marker removed: POD_NAME empty"
    return 0
  fi

  local api_opts="--connect-timeout 3 -k ${BASIC_AUTH}"
  local api_ep="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200"

  local settings_json
  settings_json=$(curl --fail ${api_opts} -s -X GET "${api_ep}/_cluster/settings?include_defaults=false&flat_settings=true" 2>/dev/null) || {
    echo "cannot read cluster settings" >&2
    return 1
  }
  local raw_exclusion
  raw_exclusion=$(echo "$settings_json" | grep -o '"persistent.cluster.routing.allocation.exclude._name" *: *"[^"]*"' | sed 's/.*: *"//;s/"$//')
  local current_exclusion
  current_exclusion=$(echo "$raw_exclusion" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | paste -sd ',' -)

  case ",$current_exclusion," in
    *",${POD_NAME},"*)
      local new_exclusion
      new_exclusion=$(echo "$current_exclusion" | tr ',' '\n' | grep -v "^${POD_NAME}$" | paste -sd ',' -)
      if [ -z "$new_exclusion" ]; then
        curl --fail ${api_opts} -s -X PUT "${api_ep}/_cluster/settings" -H 'Content-Type: application/json' -d '{"persistent":{"cluster.routing.allocation.exclude._name":null}}' >/dev/null || {
          echo "PUT clear failed" >&2
          return 1
        }
      else
        curl --fail ${api_opts} -s -X PUT "${api_ep}/_cluster/settings" -H 'Content-Type: application/json' -d "{\"persistent\":{\"cluster.routing.allocation.exclude._name\":\"${new_exclusion}\"}}" >/dev/null || {
          echo "PUT remove failed" >&2
          return 1
        }
      fi

      local verify_json
      verify_json=$(curl --fail ${api_opts} -s -X GET "${api_ep}/_cluster/settings?include_defaults=false&flat_settings=true" 2>/dev/null) || {
        echo "readback verify read failed" >&2
        return 1
      }
      local verify_exclusion
      verify_exclusion=$(echo "$verify_json" | grep -o '"persistent.cluster.routing.allocation.exclude._name" *: *"[^"]*"' | sed 's/.*: *"//;s/"$//')
      local verify_normalized
      verify_normalized=$(echo "$verify_exclusion" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | paste -sd ',' -)
      case ",$verify_normalized," in
        *",${POD_NAME},"*)
          echo "readback verify failed: ${POD_NAME} still in exclusion" >&2
          return 1
          ;;
      esac
      echo "stale exclusion cleared for ${POD_NAME}"
      ;;
    *)
      echo "no stale exclusion for ${POD_NAME}"
      ;;
  esac

  rm -f "${STALE_EXCLUSION_MARKER}"
  return 0
}

if [ "${ES_READINESS_PROBE_UNIT_TEST:-0}" = "1" ]; then
  return 0 2>/dev/null || exit 0
fi

# request Elasticsearch on /
# we are turning globbing off to allow for unescaped [] in case of IPv6
ENDPOINT="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200/"
status=$(curl -o /dev/null -w "%{http_code}" --max-time ${READINESS_PROBE_TIMEOUT} -XGET -g -s -k ${BASIC_AUTH} $ENDPOINT)
curl_rc=$?

if [[ ${curl_rc} -ne 0 ]]; then
  fail "\"curl_rc\": \"${curl_rc}\""
fi

# ready if status code 200, 503 is tolerable if ES version is 6.x
if [[ ${status} != "200" ]] ; then
  fail " \"status\": \"${status}\""
fi

if [ -f "${STALE_EXCLUSION_MARKER}" ]; then
  if try_readiness_cleanup_stale_exclusion; then
    exit 0
  else
    fail "\"phase\": \"stale-exclusion-cleanup\", \"reason\": \"cleanup failed\""
  fi
fi

exit 0
