#!/bin/sh

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
}

execute_nebula_show_space() {
  if ! /usr/local/bin/nebula-console \
    --addr "$GRAPHD_SVC_NAME" \
    --port "$GRAPHD_SVC_PORT" \
    --user root \
    --password nebula \
    -e "show spaces"; then
    return 1
  fi
  return 0
}

add_storage_host() {
  temp_file="/tmp/nebula-storaged-hosts"
  echo "ADD HOSTS \"${POD_FQDN}\":9779" > "$temp_file"

  if ! /usr/local/bin/nebula-console \
    --addr "$GRAPHD_SVC_NAME" \
    --port "$GRAPHD_SVC_PORT" \
    --user root \
    --password nebula \
    -f "$temp_file"; then
    log "Failed to add storage host"
    rm -f "$temp_file"
    return 1
  fi

  rm -f "$temp_file"
  return 0
}

# main
log "Waiting for graphd service $GRAPHD_SVC_NAME to be ready..."
until execute_nebula_show_space; do
  sleep 2
done

if add_storage_host; then
  log "Start Console succeeded!"
fi