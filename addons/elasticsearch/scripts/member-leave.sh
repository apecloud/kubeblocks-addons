#!/bin/sh
# Non-blocking memberLeave lifecycle action.
# Sets shard allocation exclusion and voting config exclusion, then returns
# immediately. Shard migration happens asynchronously; memberJoin clears
# stale exclusions when the same pod name rejoins.

set -eu

RETRY_COUNT=${RETRY_COUNT:-3}

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
common_options="-k --fail --max-time 30 --retry ${RETRY_COUNT} ${BASIC_AUTH}"

log() {
  echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

error_exit() {
  echo "ERROR: $*" >&2
  exit 1
}

if [ -z "${KB_LEAVE_MEMBER_POD_NAME:-}" ]; then
  error_exit "KB_LEAVE_MEMBER_POD_NAME environment variable is not set"
fi

node_name="$KB_LEAVE_MEMBER_POD_NAME"
log "=== memberLeave: preparing node $node_name for removal ==="

version=$(curl ${common_options} -s "${endpoint}" | jq -r .version.number)
if [ $? != 0 ]; then
  error_exit "Failed to get Elasticsearch version"
fi
major_version=${version%%.*}
log "Elasticsearch version: $version (major: $major_version)"

health=$(curl ${common_options} -s "${endpoint}/_cluster/health" | jq -r '.status')
log "Cluster health: $health"
if [ "$health" != "green" ] && [ "$health" != "yellow" ]; then
  error_exit "Cluster is not healthy (status: $health). Resolve before scaling down."
fi

is_master=$(curl ${common_options} -s "${endpoint}/_nodes/${node_name}" | jq -r '.nodes | to_entries[0].value.roles | contains(["master"])')
if [ "$is_master" = "true" ]; then
  log "Node is master-eligible — adding voting config exclusion"
  if [ "$major_version" -ge 7 ]; then
    if [ "$major_version" -eq 7 ]; then
      minor_version=$(echo "$version" | cut -d'.' -f2)
      if [ "$minor_version" -lt 8 ] 2>/dev/null; then
        vote_url="${endpoint}/_cluster/voting_config_exclusions/${node_name}"
      else
        vote_url="${endpoint}/_cluster/voting_config_exclusions?node_names=${node_name}"
      fi
    else
      vote_url="${endpoint}/_cluster/voting_config_exclusions?node_names=${node_name}"
    fi
    if ! curl ${common_options} -s -X POST "$vote_url"; then
      log "WARNING: voting exclusion failed, clearing stale entries and retrying"
      curl ${common_options} -X DELETE "${endpoint}/_cluster/voting_config_exclusions?pretty&wait_for_removal=false" || true
      curl ${common_options} -s -X POST "$vote_url" || error_exit "Failed to add voting config exclusion after clearing"
    fi
    log "Voting config exclusion set"
  fi
fi

shard_count=$(curl ${common_options} -s "${endpoint}/_cat/shards?v" | grep "$node_name" | wc -l)
log "Node $node_name currently has $shard_count shards"

current_exclusion=$(curl ${common_options} -s "${endpoint}/_cluster/settings?flat_settings=true&include_defaults=false" \
  | jq -r '.persistent["cluster.routing.allocation.exclude._name"] // ""')

case ",$current_exclusion," in
  *",$node_name,"*)
    log "Node $node_name already in shard allocation exclusion list — skipping"
    ;;
  *)
    if [ -n "$current_exclusion" ]; then
      new_exclusion="${current_exclusion},${node_name}"
    else
      new_exclusion="$node_name"
    fi
    log "Setting shard allocation exclusion: $new_exclusion"
    response=$(curl ${common_options} -s -X PUT "${endpoint}/_cluster/settings" \
      -H 'Content-Type: application/json' \
      -d "{\"persistent\": {\"cluster.routing.allocation.exclude._name\": \"${new_exclusion}\"}}")
    if [ $? != 0 ]; then
      error_exit "Failed to set shard allocation exclusion"
    fi
    echo "$response" | jq -r '.acknowledged' | grep -q "true" || error_exit "Shard exclusion not acknowledged"
    log "Shard allocation exclusion set — migration will proceed asynchronously"
    ;;
esac

log "=== memberLeave complete (non-blocking) ==="
