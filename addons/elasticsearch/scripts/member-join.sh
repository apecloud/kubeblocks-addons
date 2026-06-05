#!/bin/sh

set -eu

if [ -n "${ELASTIC_USER_PASSWORD:-}" ]; then
  BASIC_AUTH="-u elastic:${ELASTIC_USER_PASSWORD}"
else
  BASIC_AUTH=''
fi

if echo "${POD_IP:-}" | grep -q ':'; then
  LOOPBACK="[::1]"
else
  LOOPBACK=127.0.0.1
fi

if [ "${TLS_ENABLED:-false}" = "true" ]; then
  READINESS_PROBE_PROTOCOL=https
else
  READINESS_PROBE_PROTOCOL=http
fi

endpoint="${READINESS_PROBE_PROTOCOL}://${LOOPBACK}:9200"
common_options="-k --fail --max-time 30 --retry ${RETRY_COUNT:-3} ${BASIC_AUTH}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

json_escape() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

remove_name_from_csv() {
  local csv="$1"
  local remove="$2"
  printf '%s' "$csv" | tr ',' '\n' | awk -v remove="$remove" '
    {
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", $0)
      if ($0 != "" && $0 != remove) {
        if (out != "") {
          out = out "," $0
        } else {
          out = $0
        }
      }
    }
    END { print out }
  '
}

clear_stale_self_exclusion() {
  local node_name="${POD_NAME:-${KB_AGENT_POD_NAME:-${HOSTNAME:-}}}"
  if [ -z "$node_name" ]; then
    echo "ERROR: POD_NAME/KB_AGENT_POD_NAME/HOSTNAME are empty; cannot prove stale shard exclusion cleanup" >&2
    return 1
  fi

  local settings current remaining payload
  settings=$(curl ${common_options} -s "${endpoint}/_cluster/settings?flat_settings=true&include_defaults=false") || {
    echo "ERROR: failed to read cluster settings; cannot prove stale shard exclusion cleanup" >&2
    return 1
  }

  current=$(echo "$settings" | jq -r '.persistent["cluster.routing.allocation.exclude._name"] // ""') || current=""
  remaining=$(remove_name_from_csv "$current" "$node_name")
  if [ "$remaining" = "$(remove_name_from_csv "$current" "")" ]; then
    log "No stale shard allocation exclusion for node $node_name"
    return 0
  fi

  if [ -n "$remaining" ]; then
    payload="{\"persistent\":{\"cluster.routing.allocation.exclude._name\":\"$(json_escape "$remaining")\"}}"
    log "Removing node $node_name from shard allocation exclusion; remaining=$remaining"
  else
    payload='{"persistent":{"cluster.routing.allocation.exclude._name":null}}'
    log "Clearing stale shard allocation exclusion for node $node_name"
  fi

  local response
  response=$(curl ${common_options} -s -X PUT "${endpoint}/_cluster/settings" \
    -H 'Content-Type: application/json' \
    -d "$payload") || {
    echo "ERROR: failed to update shard allocation exclusion during memberJoin" >&2
    return 1
  }

  echo "$response" | jq -r '.acknowledged' | grep -q "true" || {
    echo "ERROR: shard allocation exclusion update was not acknowledged" >&2
    return 1
  }
}

clear_stale_self_exclusion
