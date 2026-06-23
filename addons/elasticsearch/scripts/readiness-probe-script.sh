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

STALE_EXCLUSION_MARKER="/tmp/stale-exclusion-cleanup.pending"
if [ -f "${STALE_EXCLUSION_MARKER}" ]; then
  if [ -z "${POD_NAME:-}" ]; then
    rm -f "${STALE_EXCLUSION_MARKER}"
    exit 0
  fi

  COMMON_OPTIONS="--connect-timeout 3 -k ${BASIC_AUTH}"
  API_ENDPOINT="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200"

  settings_json=$(curl --fail ${COMMON_OPTIONS} -s -X GET "${API_ENDPOINT}/_cluster/settings?include_defaults=false&flat_settings=true" 2>/dev/null) || {
    fail "\"phase\": \"stale-exclusion-cleanup\", \"reason\": \"cannot read cluster settings\""
  }
  raw_exclusion=$(echo "$settings_json" | grep -o '"persistent.cluster.routing.allocation.exclude._name" *: *"[^"]*"' | sed 's/.*: *"//;s/"$//')
  current_exclusion=$(echo "$raw_exclusion" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | paste -sd ',' -)

  case ",$current_exclusion," in
    *",${POD_NAME},"*)
      new_exclusion=$(echo "$current_exclusion" | tr ',' '\n' | grep -v "^${POD_NAME}$" | paste -sd ',' -)
      if [ -z "$new_exclusion" ]; then
        curl --fail ${COMMON_OPTIONS} -s -X PUT "${API_ENDPOINT}/_cluster/settings" -H 'Content-Type: application/json' -d '{"persistent":{"cluster.routing.allocation.exclude._name":null}}' >/dev/null || {
          fail "\"phase\": \"stale-exclusion-cleanup\", \"reason\": \"PUT clear failed\""
        }
      else
        curl --fail ${COMMON_OPTIONS} -s -X PUT "${API_ENDPOINT}/_cluster/settings" -H 'Content-Type: application/json' -d "{\"persistent\":{\"cluster.routing.allocation.exclude._name\":\"${new_exclusion}\"}}" >/dev/null || {
          fail "\"phase\": \"stale-exclusion-cleanup\", \"reason\": \"PUT remove failed\""
        }
      fi

      verify_json=$(curl --fail ${COMMON_OPTIONS} -s -X GET "${API_ENDPOINT}/_cluster/settings?include_defaults=false&flat_settings=true" 2>/dev/null) || {
        fail "\"phase\": \"stale-exclusion-cleanup\", \"reason\": \"readback verify read failed\""
      }
      verify_exclusion=$(echo "$verify_json" | grep -o '"persistent.cluster.routing.allocation.exclude._name" *: *"[^"]*"' | sed 's/.*: *"//;s/"$//')
      verify_normalized=$(echo "$verify_exclusion" | tr ',' '\n' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | grep -v '^$' | paste -sd ',' -)
      case ",$verify_normalized," in
        *",${POD_NAME},"*)
          fail "\"phase\": \"stale-exclusion-cleanup\", \"reason\": \"readback verify failed, ${POD_NAME} still in exclusion\""
          ;;
      esac
      ;;
  esac

  rm -f "${STALE_EXCLUSION_MARKER}"
fi

exit 0