#!/usr/bin/env bash

function info() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

if [ "${TLS_ENABLED}" == "true" ]; then
  READINESS_PROBE_PROTOCOL=https
else
  READINESS_PROBE_PROTOCOL=http
fi

# All the components' password of elastic must be the same, So we find the first environment variable that starts with ELASTIC_USER_PASSWORD
ELASTIC_AUTH_PASSWORD=""
if [ "${TLS_ENABLED}" == "true" ]; then
  last_value=""
  set +x
  for env_var in $(env | grep -E '^ELASTIC_USER_PASSWORD'); do
    value="${env_var#*=}"
    if [ -n "$value" ]; then
      if [ -n "$last_value" ] && [ "$last_value" != "$value" ]; then
        echo "Error conflicting env $env_var of elastic password values found, all the components' password of elastic must be the same."
        exit 1
      fi
      last_value="$value"
    fi
  done
  ELASTIC_AUTH_PASSWORD="$last_value"
fi

for env_var in $(env | grep -E '^ELASTICSEARCH_HOST'); do
  value="${env_var#*=}"
  if [ -n "$value" ]; then
    ELASTICSEARCH_HOST="$value"
    break
  fi
done

if [ -z "$ELASTICSEARCH_HOST" ]; then
  echo "Invalid ELASTICSEARCH_HOST"
  exit 1
fi

endpoint="${READINESS_PROBE_PROTOCOL}://${ELASTICSEARCH_HOST}.${CLUSTER_NAMESPACE}.svc.${CLUSTER_DOMAIN}:9200"
common_options="-s -u elastic:${ELASTIC_AUTH_PASSWORD} --fail --connect-timeout 3 -k"

while true; do
  if [ "${TLS_ENABLED}" == "true" ]; then
    out=$(curl ${common_options} -X GET "${endpoint}/kubeblocks_ca_crt/_doc/1?pretty")
    if [ $? == 0 ]; then
      echo "$out" | grep '"ca.crt" :' | awk -F: '{print $2}' | tr -d '",' | xargs | base64 -d > /tmp/elastic.ca.crt
      info "elasticsearch is ready"
      break
    fi
  else
    curl ${common_options} -X GET "${endpoint}"
    if [ $? == 0 ]; then
      info "elasticsearch is ready"
      break
    fi
  fi
  info "waiting for elasticsearch to be ready"
  sleep 1
done

if [ -f /bin/tini ]; then
  /bin/tini -- /usr/local/bin/kibana-docker -e "${endpoint}" -H "${POD_IP}"
else
  /usr/local/bin/kibana-docker -e "${endpoint}" -H "${POD_IP}"
fi
