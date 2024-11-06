#!/bin/sh

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

execute_nebula_command() {
  host_file="$1"
  if ! /usr/local/bin/nebula-console \
    --addr "$GRAPHD_SVC_NAME" \
    --port "$GRAPHD_SVC_PORT" \
    --user root \
    --password nebula \
    -f "$host_file"; then
    log "Failed to execute nebula-console command" >&2
    return 1
  fi
  return 0
}

process_storage_cleanup() {
  idx="${KB_LEAVE_MEMBER_POD_NAME##*-}"
  current_component_replicas="$STORAGED_COMPONENT_REPLICAS"
  echo "Current component replicas: $current_component_replicas, member leave pod name: $KB_LEAVE_MEMBER_POD_NAME, idx: $idx"
  if [ ! $idx -lt $current_component_replicas ] && [ $current_component_replicas -ne 0 ]; then
    temp_file="/tmp/nebula-storaged-hosts"

    LEAVE_MEMBER_POD_FQDN="$KB_LEAVE_MEMBER_POD_NAME.$STORAGED_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CUSTER_DOMAIN"
    echo "DROP HOSTS \"$LEAVE_MEMBER_POD_FQDN\":9779" > "$temp_file"

    execute_nebula_command "$temp_file"
    status=$?

    rm -f "$temp_file"
    return $status
  fi
  return 0
}

# main
process_storage_cleanup