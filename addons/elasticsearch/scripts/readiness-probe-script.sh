#!/usr/bin/env bash

# fail should be called as a last resort to help the user to understand why the probe failed
function fail {
  timestamp=$(date --iso-8601=seconds)
  echo "{\"timestamp\": \"${timestamp}\", \"message\": \"readiness probe failed\", "$1"}" | tee /proc/1/fd/2 2> /dev/null
  exit 1
}

READINESS_PROBE_TIMEOUT=${READINESS_PROBE_TIMEOUT:=3}

if [ -n "${KB_TLS_CERT_FILE}" ]; then
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
if [[ ${status} == "200" ]] ; then
  exit 0
else
  fail " \"status\": \"${status}\""
fi