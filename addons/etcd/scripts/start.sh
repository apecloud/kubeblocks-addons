#!/bin/bash

default_template_conf="/etc/etcd/etcd.conf"
real_conf="$TMP_CONFIG_PATH"

load_common_library() {
  # the kb-common.sh and common.sh scripts are defined in the scripts-template configmap
  # and are mounted to the same path which defined in the cmpd.spec.scripts
  kblib_common_library_file="/scripts/kb-common.sh"
  etcd_common_library_file="/scripts/common.sh"
  # shellcheck source=/scripts/kb-common.sh
  . "${kblib_common_library_file}"
  # shellcheck source=/scripts/common.sh
  . "${etcd_common_library_file}"
}

log() {
  echo "[$(date +'%Y-%m-%d %H:%M:%S')] $1"
}

get_my_endpoint() {
  # shellcheck disable=SC2153
  if is_empty "$CURRENT_POD_NAME" || is_empty "$PEER_FQDNS"; then
    echo "Error: PEER_FQDNS or CURRENT_POD_NAME is empty. Exiting." >&2
    return 1
  fi

  peer_endpoints="$1"
  current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$PEER_FQDNS" "$CURRENT_POD_NAME")
  if is_empty "$current_pod_fqdn"; then
    echo "Error: Failed to get current pod: $CURRENT_POD_NAME fqdn from peer fqdn list: $PEER_FQDNS. Exiting." >&2
    return 1
  fi

  my_peer_endpoint="$current_pod_fqdn"
  if ! is_empty "$peer_endpoints"; then
    log "LoadBalancer mode detected. Adapting pod FQDN to balance IP." >&2
    endpoints=$(echo "$peer_endpoints" | tr ',' '\n')
    my_endpoint=$(echo "$endpoints" | grep "$CURRENT_POD_NAME")

    if is_empty "$my_endpoint"; then
      log "Failed to get my peer endpoint from PEER_FQDNS:$PEER_FQDNS when loadBalancer mode is enabled, use default pod FQDN to advertise." >&2
    else
      # e.g.1 etcd-cluster-etcd-0
      # e.g.2 etcd-cluster-etcd-0:127.0.0.1
      if echo "$my_endpoint" | grep -q ":"; then
        my_peer_endpoint=$(echo "$my_endpoint" | cut -d: -f2)
      else
        my_peer_endpoint=$my_endpoint
      fi
    fi
  fi

  echo "$my_peer_endpoint"
  return 0
}

update_etcd_conf() {
  default_template_conf="$1"
  tpl_conf="$2"
  current_pod_name="$3"
  my_endpoint="$4"

  cp "$default_template_conf" "$tpl_conf"

  sed -i.bak "s/^name:.*/name: $current_pod_name/g" "$tpl_conf"
  sed -i.bak "s#\(initial-advertise-peer-urls: http\(s\{0,1\}\)://\).*#\1$my_endpoint:2380#g" "$tpl_conf"
  sed -i.bak "s#\(advertise-client-urls: http\(s\{0,1\}\)://\).*#\1$my_endpoint:2379#g" "$tpl_conf"
  rm "$tpl_conf.bak"
}

rebuild_etcd_conf() {
  # According to https://etcd.io/docs/v3.5/op-guide/configuration/
  # etcd ignores command-line flags and environment variables if a configuration file is provided.
  # need to copy the configuration file and modify it
  log "start to rebuild etcd configuration..."
  my_endpoint=$(get_my_endpoint "$PEER_ENDPOINT")
  status=$?
  if [ "$status" -ne 0 ]; then
      log "Failed to get my endpoint. Exiting." >&2
      return 1
  fi
  update_etcd_conf "$default_template_conf" "$real_conf" "$CURRENT_POD_NAME" "$my_endpoint"

  log "Updated etcd.conf:"
  cat "$real_conf"
  log "---"
  return 0
}

main() {
  # rebuild etcd configuration
  if rebuild_etcd_conf; then
    log "Rebuilt etcd configuration successfully."
  else
    log "Failed to rebuild etcd configuration." >&2
    exit 1
  fi

  # start etcd
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