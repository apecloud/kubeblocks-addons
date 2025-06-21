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

get_my_endpoint() {
  my_peer_endpoint=$(get_target_pod_fqdn_from_pod_fqdn_vars "$PEER_FQDNS" "$CURRENT_POD_NAME")
  [ -z "$my_peer_endpoint" ] && error_exit "Failed to get current pod: $CURRENT_POD_NAME fqdn from peer fqdn list: $PEER_FQDNS"
  my_peer_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$CURRENT_POD_NAME" "$my_peer_endpoint")
  echo "$my_peer_endpoint"
}

update_etcd_conf() {
  local default_template_conf="$1"
  local tpl_conf="$2"
  local current_pod_name="$3"
  local my_endpoint="$4"

  if [ ! -e "$tpl_conf" ]; then
    cp "$default_template_conf" "$tpl_conf"
  else
    immutable_params=("initial-cluster" "initial-cluster-token" "initial-cluster-state" "force-new-cluster")
    temp_conf="${tpl_conf}.tmp"
    cp "$default_template_conf" "$temp_conf"
    for param in "${immutable_params[@]}"; do
      if existing_line=$(grep -E "^${param}:" "$tpl_conf"); then
        sed -i.bak "s|^${param}:.*|${existing_line}|g" "$temp_conf"
      fi
    done
    rm "$temp_conf.bak"
    mv "$temp_conf" "$tpl_conf"
  fi

  peer_protocol=$(get_protocol "initial-advertise-peer-urls")
  client_protocol=$(get_protocol "advertise-client-urls")
  my_endpoint=$(get_endpoint_adapt_lb "$PEER_ENDPOINT" "$current_pod_name" "$my_endpoint")

  sed -i.bak "s|^name:.*|name: $current_pod_name|g" "$tpl_conf"
  sed -i.bak "s|^initial-advertise-peer-urls:.*|initial-advertise-peer-urls: $peer_protocol://$my_endpoint:2380|g" "$tpl_conf"
  sed -i.bak "s|^advertise-client-urls:.*|advertise-client-urls: $client_protocol://$my_endpoint:2379|g" "$tpl_conf"
  rm "$tpl_conf.bak"
}

rebuild_etcd_conf() {
  my_endpoint=$(get_my_endpoint)
  update_etcd_conf "$default_template_conf" "$default_conf" "$CURRENT_POD_NAME" "$my_endpoint"

  log "Updated etcd.conf:"
  cat "$default_conf"
}

restore() {
  files=("$RESTORE_DIR"/*)
  if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
    error_exit "No backup file found in $RESTORE_DIR or directory is empty."
  fi

  backup_file="${files[0]}"
  check_backup_file "$backup_file" || error_exit "Backup file is invalid"

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
  rebuild_etcd_conf

  if [ -d "$RESTORE_DIR" ]; then
    restore
  fi

  log "Starting etcd with updated configuration..."
  exec etcd --config-file "$default_conf"
}

# Shellspec magic
setup_shellspec

# main
load_common_library
main "$@"
