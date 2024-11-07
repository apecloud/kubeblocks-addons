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
    echo "Failed to execute nebula-console show spaces command" >&2
    return 1
  fi
  return 0
}

add_storage_host() {
  temp_file="/tmp/nebula-storaged-hosts"
  add_host_cmd="ADD HOSTS \"${POD_FQDN}\":9779"
  log "Add storage host command: ${add_host_cmd}"
  echo "${add_host_cmd}" > "${temp_file}"

  if ! /usr/local/bin/nebula-console \
    --addr "$GRAPHD_SVC_NAME" \
    --port "$GRAPHD_SVC_PORT" \
    --user root \
    --password nebula \
    -f "$temp_file"; then
    log "Failed to add storage host" >&2
    rm -f "$temp_file"
    return 1
  fi

  rm -f "$temp_file"
  return 0
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
log "Waiting for graphd service $GRAPHD_SVC_NAME to be ready..."
until execute_nebula_show_space; do
  sleep 2
done

if add_storage_host; then
  log "Start Console succeeded!"
fi