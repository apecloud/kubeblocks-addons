#!/usr/bin/env bash

# Disable nss cache to avoid filling dentry cache when calling curl.
# This is required with Kibana Docker using nss < 3.52.
export NSS_SDB_USE_CACHE=no

http() {
  local path="${1}"
  set -- -XGET -s --fail -L

  if [ -n "${ELASTICSEARCH_USERNAME}" ] && [ -n "${ELASTICSEARCH_PASSWORD}" ]; then
    set -- "$@" -u "${ELASTICSEARCH_USERNAME}:${ELASTICSEARCH_PASSWORD}"
  fi

  if [ "${TLS_ENABLED}" == "true" ]; then
    READINESS_PROBE_PROTOCOL=https
  else
    READINESS_PROBE_PROTOCOL=http
  fi
  endpoint="${READINESS_PROBE_PROTOCOL}://${POD_IP}:5601"
  STATUS=$(curl --output /dev/null --write-out "%{http_code}" -k "$@" "${endpoint}${path}")
  if [[ "${STATUS}" -eq 200 ]]; then
    exit 0
  fi

  echo "Error: Got HTTP code ${STATUS} but expected a 200"
  exit 1
}

http "/app/kibana"
