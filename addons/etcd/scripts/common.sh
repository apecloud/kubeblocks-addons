#!/bin/bash

# config file used to bootstrap the etcd cluster
config_file="$TMP_CONFIG_PATH"

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

error_exit() {
  log "ERROR: $1" >&2
  exit 1
}

# execute etcdctl command with proper TLS settings and auto protocol detection
exec_etcdctl() {
  local endpoint="$1"
  shift

  # Auto-detect protocol and add prefix if not present
  if [[ "$endpoint" != http://* ]] && [[ "$endpoint" != https://* ]]; then
    if grep -q "^advertise-client-urls:.*https://" "$config_file"; then
      endpoint="https://$endpoint"
    else
      endpoint="http://$endpoint"
    fi
  fi

  if grep -q "^advertise-client-urls:.*https://" "$config_file"; then
    [ ! -d "$TLS_MOUNT_PATH" ] && echo "ERROR: TLS_MOUNT_PATH '$TLS_MOUNT_PATH' not found" >&2 && return 1
    for cert in ca.pem cert.pem key.pem; do
      [ ! -s "$TLS_MOUNT_PATH/$cert" ] && echo "ERROR: TLS certificate '$cert' missing or empty" >&2 && return 1
    done
    etcdctl --endpoints="$endpoint" --cacert="$TLS_MOUNT_PATH/ca.pem" --cert="$TLS_MOUNT_PATH/cert.pem" --key="$TLS_MOUNT_PATH/key.pem" "$@"
  else
    etcdctl --endpoints="$endpoint" "$@"
  fi
}

get_client_protocol() {
  local line

  if [ ! -f "$config_file" ]; then
    error_exit "get_client_protocol - Config file '$config_file' not found"
  fi
  line=$(grep "advertise-client-urls" "$config_file" || true)
  if echo "$line" | grep -q 'https'; then
    echo "https"
  else
    echo "http"
  fi
}

get_peer_protocol() {
  local line

  if [ ! -f "$config_file" ]; then
    error_exit "get_peer_protocol - Config file '$config_file' not found"
  fi
  line=$(grep "initial-advertise-peer-urls" "$config_file" || true)
  if echo "$line" | grep -q 'https'; then
    echo "https"
  else
    echo "http"
  fi
}

# For backward compatibility
get_protocol() {
  get_client_protocol
}

check_backup_file() {
  local backup_file="$1"

  if [ ! -f "$backup_file" ]; then
    echo "ERROR: Backup file $backup_file does not exist" >&2
    return 1
  fi
  etcdutl snapshot status "$backup_file"
}

get_pod_endpoint_with_lb() {
  local peer_endpoints="$1"
  local pod_name="$2"
  local default_fqdn="$3"
  local result_endpoint="$default_fqdn"
  
  if ! is_empty "$peer_endpoints"; then
    log "LoadBalancer mode detected. Adapting pod FQDN to balance IP."
    local endpoints lb_endpoint
    endpoints=$(echo "$peer_endpoints" | tr ',' '\n')
    lb_endpoint=$(echo "$endpoints" | grep "$pod_name" | head -1)
    if ! is_empty "$lb_endpoint"; then
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
