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

member_join() {
  local my_endpoint="$1"
  local current_pod_name="$2"
  local peer_protocol="$3"

  log "HScale detected - joining existing cluster"
  leader_endpoint=$(find_leader_endpoint "$PEER_FQDNS" "$PEER_ENDPOINT" "$my_endpoint")
  [ -z "$leader_endpoint" ] && error_exit "Failed to find leader in existing cluster"
  exec_etcdctl "$leader_endpoint:2379" member add "$current_pod_name" --peer-urls="$peer_protocol://$my_endpoint:2380" || error_exit "Failed to join member"
  log "Member $current_pod_name joined cluster via leader $leader_endpoint"
}

update_etcd_conf() {
  local my_endpoint="$1"

  cp "$default_template_conf" "$default_conf"
  local peer_protocol client_protocol
  peer_protocol=$(get_protocol "initial-advertise-peer-urls")
  client_protocol=$(get_protocol "advertise-client-urls")

  sed -i.bak "s|^name:.*|name: $CURRENT_POD_NAME|g" "$default_conf"
  sed -i.bak "s|^initial-advertise-peer-urls:.*|initial-advertise-peer-urls: $peer_protocol://$my_endpoint:2380|g" "$default_conf"
  sed -i.bak "s|^advertise-client-urls:.*|advertise-client-urls: $client_protocol://$my_endpoint:2379|g" "$default_conf"

  if [ -f "/var/run/etcd/hscale-flag" ]; then
    member_join "$my_endpoint" "$CURRENT_POD_NAME" "$peer_protocol"
    sed -i.bak "s/^initial-cluster-state: 'new'/initial-cluster-state: 'existing'/g" "$default_conf"
    rm "/var/run/etcd/hscale-flag"
  fi

  rm -f "$default_conf.bak"
}

restore() {
  if [ -d "$DATA_DIR" ]; then
    if [ -n "$(find "$DATA_DIR" -mindepth 1 -print -quit 2>/dev/null)" ]; then
      log "Existing data directory $DATA_DIR detected, skipping snapshot restore when restart etcd"
      return 0
    fi
  fi

  files=("$BACKUP_DIR"/*)
  [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ] && error_exit "No backup file found in $BACKUP_DIR or directory is empty."

  local backup_file="${files[0]}"
  check_backup_file "$backup_file"

  name=$(parse_config_value "name" "$default_conf")
  advertise_urls=$(parse_config_value "initial-advertise-peer-urls" "$default_conf")
  cluster=$(parse_config_value "initial-cluster" "$default_conf")
  cluster_token=$(parse_config_value "initial-cluster-token" "$default_conf")

  etcdutl snapshot restore "$backup_file" \
    --data-dir="$DATA_DIR" \
    --name="$name" \
    --initial-advertise-peer-urls="$advertise_urls" \
    --initial-cluster="$cluster" \
    --initial-cluster-token="$cluster_token"
  rm -rf "$BACKUP_DIR"
}

start() {
  local my_endpoint
  my_endpoint=$(get_my_endpoint)
  update_etcd_conf "$my_endpoint"

  log "Updated etcd.conf:"
  cat "$default_conf"

  if [ -d "$BACKUP_DIR" ]; then
    restore
  fi

  log "Starting etcd with updated configuration..."
  exec etcd --config-file "$default_conf"
}

# main
start "$@"
