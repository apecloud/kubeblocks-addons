#!/bin/bash
set -ex

default_template_conf="/etc/etcd/etcd.conf"
real_conf="$TMP_CONFIG_PATH"

load_common_library() {
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck disable=SC1090
  . "${kblib_common_library_file}"
  # shellcheck disable=SC1090
  . "${etcd_common_library_file}"
}

get_my_endpoint() {
  local lb_endpoints="$1"
  local my_peer_endpoint

  if is_empty "$CURRENT_POD_NAME" || is_empty "$PEER_FQDNS"; then
    echo "Error: CURRENT_POD_NAME or PEER_FQDNS is empty. Exiting." >&2
    return 1
  fi

  my_peer_endpoint=$(get_target_pod_fqdn_from_pod_fqdn_vars "$PEER_FQDNS" "$CURRENT_POD_NAME")
  if is_empty "$my_peer_endpoint"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from peer fqdn list: $PEER_FQDNS. Exiting." >&2
    return 1
  fi

  my_peer_endpoint=$(get_pod_endpoint_with_lb "$CURRENT_POD_NAME" "$my_peer_endpoint")
  echo "$my_peer_endpoint"
}

update_etcd_conf() {
  local default_template_conf="$1"
  local tpl_conf="$2"
  local current_pod_name="$3"
  local my_endpoint="$4"
  local peer_protocol client_protocol

  if [ ! -e "$tpl_conf" ]; then
    cp "$default_template_conf" "$tpl_conf"
  fi

  peer_protocol=$(get_peer_protocol)
  client_protocol=$(get_client_protocol)

  sed -i.bak "s/^name:.*/name: $current_pod_name/g" "$tpl_conf"
  sed -i.bak "s|^initial-advertise-peer-urls:.*|initial-advertise-peer-urls: $peer_protocol://$my_endpoint:2380|g" "$tpl_conf"
  sed -i.bak "s|^advertise-client-urls:.*|advertise-client-urls: $client_protocol://$my_endpoint:2379|g" "$tpl_conf"
  rm "$tpl_conf.bak"
}

parse_config_value() {
  local key="$1"
  local config_file="$2"
  grep -E "^$key:" "$config_file" |
    sed -E \
      -e "s/^$key:[[:space:]]*//" \
      -e 's/^[[:space:]]*//; s/[[:space:]]*$//'
}

rebuild_etcd_conf() {
  local my_endpoint
  my_endpoint=$(get_my_endpoint "$PEER_ENDPOINT")
  update_etcd_conf "$default_template_conf" "$real_conf" "$CURRENT_POD_NAME" "$my_endpoint"

  log "Updated etcd.conf:"
  cat "$real_conf"
}

restore() {
  local files backup_file data_dir name advertise_urls cluster cluster_token

  files=("$RESTORE_DIR"/*)
  if [ ${#files[@]} -eq 0 ] || [ ! -e "${files[0]}" ]; then
      log "No backup file found in $RESTORE_DIR or directory is empty."
      exit 1
  fi
  backup_file="${files[0]}"

  check_backup_file "$backup_file"

  data_dir=$(parse_config_value "data-dir" "$real_conf")
  name=$(parse_config_value "name" "$real_conf")
  advertise_urls=$(parse_config_value "initial-advertise-peer-urls" "$real_conf")
  cluster=$(parse_config_value "initial-cluster" "$real_conf")
  cluster_token=$(parse_config_value "initial-cluster-token" "$real_conf")
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

  if [ -e "$RESTORE_DIR" ]; then
    restore
  fi

  log "Starting etcd with updated configuration..."
  exec etcd --config-file "$real_conf"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
main "$@"
