#!/bin/bash
set -exo pipefail

default_template_conf="$CONFIG_TEMPLATE_PATH"
default_conf="$CONFIG_FILE_PATH"

# shellcheck disable=SC1091
. "/scripts/common.sh"

parse_config_value() {
  local key="$1"
  local config_file="$2"
  grep "^$key:" "$config_file" | cut -d: -f2- | xargs
}

setup_protocols_and_cluster() {
  peer_protocol="http"
  client_protocol="http"

  [ "$TLS_ENABLED" = "true" ] && [ "$PEER_TLS" = "true" ] && peer_protocol="https"
  [ "$TLS_ENABLED" = "true" ] && [ "$CLIENT_TLS" = "true" ] && client_protocol="https"

  log "Set protocols: peer=$peer_protocol, client=$client_protocol"

  # Get my endpoint
  my_peer_endpoint=$(get_target_pod_fqdn_from_pod_fqdn_vars "$PEER_FQDNS" "$CURRENT_POD_NAME")
  [ -z "$my_peer_endpoint" ] && error_exit "Failed to get current pod: $CURRENT_POD_NAME fqdn from peer fqdn list: $PEER_FQDNS"
  my_peer_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$CURRENT_POD_NAME" "$my_peer_endpoint")

  # Generate cluster configuration
  cluster_config=""
  if [ -n "$PEER_ENDPOINT" ]; then
    log "Using PEER_ENDPOINT for cluster configuration"
    IFS=',' read -ra endpoints <<<"$PEER_ENDPOINT"
    if [ "${#endpoints[@]}" -ne "$COMPONENT_REPLICAS" ]; then
      log "PEER_ENDPOINT cannot parse enough endpoints, fallback to use PEER_FQDNS"
    else
      for endpoint in "${endpoints[@]}"; do
        local hostname target_endpoint
        if [[ "$endpoint" == *":"* ]]; then
          hostname="${endpoint%:*}"
          target_endpoint="${endpoint#*:}"
        else
          hostname="$endpoint"
          target_endpoint="$endpoint"
        fi
        target_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$hostname" "$target_endpoint")
        cluster_config="${cluster_config:+$cluster_config,}$hostname=$peer_protocol://$target_endpoint:2380"
      done
      return
    fi
  fi

  if [ -n "$PEER_FQDNS" ]; then
    log "Using PEER_FQDNS for cluster configuration"
    IFS=',' read -ra fqdns <<<"$PEER_FQDNS"
    for fqdn in "${fqdns[@]}"; do
      local hostname="${fqdn%%.*}"
      cluster_config="${cluster_config:+$cluster_config,}$hostname=$peer_protocol://$fqdn:2380"
    done
    return
  fi

  error_exit "Neither PEER_ENDPOINT nor PEER_FQDNS is available"
}

update_etcd_conf() {
  # retain initial-cluster-state, which may be set by data-load.sh
  [ -f "$default_conf" ] && initial_cluster_state=$(parse_config_value "initial-cluster-state" "$default_conf")
  cp "$default_template_conf" "$default_conf"
  [ -n "$initial_cluster_state" ] && sed -i.bak "s|^initial-cluster-state:.*|initial-cluster-state: $initial_cluster_state|g" "$default_conf"

  setup_protocols_and_cluster

  local client_auth="false"
  local peer_auth="false"
  [ "$client_protocol" = "https" ] && client_auth="true"
  [ "$peer_protocol" = "https" ] && peer_auth="true"

  {
    sed -i.bak "s|^name:.*|name: $CURRENT_POD_NAME|g" "$default_conf"
    sed -i.bak "s|^initial-cluster-token:.*|initial-cluster-token: $CLUSTER_NAME|g" "$default_conf"
    sed -i.bak "s|^listen-peer-urls:.*|listen-peer-urls: $peer_protocol://0.0.0.0:2380|g" "$default_conf"
    sed -i.bak "s|^listen-client-urls:.*|listen-client-urls: $client_protocol://0.0.0.0:2379|g" "$default_conf"
    sed -i.bak "s|^initial-advertise-peer-urls:.*|initial-advertise-peer-urls: $peer_protocol://$my_peer_endpoint:2380|g" "$default_conf"
    sed -i.bak "s|^advertise-client-urls:.*|advertise-client-urls: $client_protocol://$my_peer_endpoint:2379|g" "$default_conf"
    sed -i.bak "s|^initial-cluster:.*|initial-cluster: $cluster_config|g" "$default_conf"
  }

  if [ "$TLS_ENABLED" = "true" ]; then
    if [ "$client_protocol" = "https" ]; then
      sed -i.bak "/^client-transport-security:$/a\\
  cert-file: $TLS_MOUNT_PATH/cert.pem\\
  key-file: $TLS_MOUNT_PATH/key.pem\\
  client-cert-auth: $client_auth\\
  trusted-ca-file: $TLS_MOUNT_PATH/ca.pem\\
  auto-tls: false" "$default_conf"
    fi
    
    if [ "$peer_protocol" = "https" ]; then
      sed -i.bak "/^peer-transport-security:$/a\\
  cert-file: $TLS_MOUNT_PATH/cert.pem\\
  key-file: $TLS_MOUNT_PATH/key.pem\\
  client-cert-auth: $peer_auth\\
  trusted-ca-file: $TLS_MOUNT_PATH/ca.pem\\
  auto-tls: false\\
  allowed-cn:\\
  allowed-hostname:" "$default_conf"
    fi
  else
    sed -i.bak '/^client-transport-security:/d' "$default_conf"
    sed -i.bak '/^peer-transport-security:/d' "$default_conf"
  fi

  rm -f "$default_conf.bak"
}

restore() {
  files=("$RESTORE_DIR"/*)
  [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ] && error_exit "No backup file found in $RESTORE_DIR or directory is empty."

  backup_file="${files[0]}"
  check_backup_file "$backup_file"

  data_dir=$(parse_config_value "data-dir" "$default_conf")
  name=$(parse_config_value "name" "$default_conf")
  advertise_urls=$(parse_config_value "initial-advertise-peer-urls" "$default_conf")
  cluster=$(parse_config_value "initial-cluster" "$default_conf")
  cluster_token=$(parse_config_value "initial-cluster-token" "$default_conf")

  etcdutl snapshot restore "$backup_file" \
    --data-dir="$data_dir" \
    --name="$name" \
    --initial-advertise-peer-urls="$advertise_urls" \
    --initial-cluster="$cluster" \
    --initial-cluster-token="$cluster_token"
  rm -rf "$RESTORE_DIR"
}

main() {
  update_etcd_conf

  log "Updated etcd.conf:"
  cat "$default_conf"

  [ -d "$RESTORE_DIR" ] && restore

  log "Starting etcd with updated configuration..."
  exec etcd --config-file "$default_conf"
}

# Shellspec magic
setup_shellspec

# main
load_common_library
main "$@"
