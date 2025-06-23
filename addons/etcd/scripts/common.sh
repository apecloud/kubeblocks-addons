#!/var/run/etcd/bin/bash
export PATH=/var/run/etcd/bin:$PATH
# config file used to bootstrap the etcd cluster
config_file="$CONFIG_FILE_PATH"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1" >&2
}

error_exit() {
  log "ERROR: $1"
  exit 1
}

# Standard library loading function - can be sourced by all scripts
load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

# Standard shellspec magic - can be used by all scripts
setup_shellspec() {
  ${__SOURCED__:+false} : || return 0
}

# execute etcdctl command with auto protocol detection
exec_etcdctl() {
  local endpoint="$1"
  shift

  if [[ "$endpoint" != http://* ]] && [[ "$endpoint" != https://* ]]; then
    if get_protocol "advertise-client-urls" | grep -q "https"; then
      endpoint="https://$endpoint"
    else
      endpoint="http://$endpoint"
    fi
  fi

  if get_protocol "advertise-client-urls" | grep -q "https"; then
    [ ! -d "$TLS_MOUNT_PATH" ] && echo "ERROR: TLS_MOUNT_PATH '$TLS_MOUNT_PATH' not found" >&2 && return 1
    for cert in ca.pem cert.pem key.pem; do
      [ ! -s "$TLS_MOUNT_PATH/$cert" ] && echo "ERROR: TLS certificate '$cert' missing or empty" >&2 && return 1
    done
    etcdctl --endpoints="$endpoint" --cacert="$TLS_MOUNT_PATH/ca.pem" --cert="$TLS_MOUNT_PATH/cert.pem" --key="$TLS_MOUNT_PATH/key.pem" "$@"
  else
    etcdctl --endpoints="$endpoint" "$@"
  fi
}

get_protocol() {
  local url_type="$1"

  if grep "$url_type" "$config_file" | grep -q 'https'; then
    echo "https"
  else
    echo "http"
  fi
}

check_backup_file() {
  local backup_file="$1"

  if [ ! -e "$backup_file" ]; then
    error_exit "Backup file $backup_file does not exist"
  fi
  etcdutl snapshot status "$backup_file"
}

get_endpoint_adapt_lb() {
  local lb_endpoints="$1"
  local pod_name="$2"
  local result_endpoint="$3"

  if [ -n "$lb_endpoints" ]; then
    log "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
    local endpoints lb_endpoint
    endpoints=$(echo "$lb_endpoints" | tr ',' '\n')
    lb_endpoint=$(echo "$endpoints" | grep "$pod_name" | head -1)
    if [ -n "$lb_endpoint" ]; then
      # e.g.1 etcd-cluster-etcd-0
      # e.g.2 etcd-cluster-etcd-0:127.0.0.1
      if echo "$lb_endpoint" | grep -q ":"; then
        result_endpoint=$(echo "$lb_endpoint" | cut -d: -f2)
      else
        result_endpoint="$lb_endpoint"
      fi
      log "Using LoadBalancer endpoint for $pod_name: $result_endpoint"
    else
      log "Failed to get LB endpoint for $pod_name, using default FQDN: $result_endpoint"
    fi
  fi
  echo "$result_endpoint"
}

parse_endpoint_field() {
  local endpoint="$1"
  local field_name="$2"
  local status field_value

  if ! status=$(exec_etcdctl "$endpoint" endpoint status -w fields); then
    error_exit "Failed to get endpoint status from $endpoint"
  fi

  field_value=$(echo "$status" | awk -F': ' -v field="\"$field_name\"" '$1 ~ field {gsub(/[^0-9]/, "", $2); print $2}')

  [ -z "$field_value" ] && error_exit "Failed to extract $field_name from endpoint status"

  echo "$field_value"
}

is_leader() {
  local contact_point="$1"
  local member_id leader_id

  member_id=$(parse_endpoint_field "$contact_point" "MemberID")
  leader_id=$(parse_endpoint_field "$contact_point" "Leader")

  [ "$member_id" = "$leader_id" ]
}

get_member_and_leader_id() {
  local endpoint="$1"

  member_id=$(parse_endpoint_field "$endpoint" "MemberID")
  leader_id=$(parse_endpoint_field "$endpoint" "Leader")

  echo "$member_id $leader_id"
}

get_member_id() {
  local endpoint="$1"
  parse_endpoint_field "$endpoint" "MemberID"
}

get_member_id_hex() {
  local endpoint="$1"
  member_id=$(parse_endpoint_field "$endpoint" "MemberID")
  printf "%x" "$member_id"
}
