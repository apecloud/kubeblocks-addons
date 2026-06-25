#!/usr/bin/env bash

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/qdrant/scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

# get the min lexicographical order pod fqdn as the bootstrap node
get_boostrap_node() {
  min_lexicographical_pod_name=$(min_lexicographical_order_pod "$QDRANT_POD_NAME_LIST")
  min_lexicographical_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$QDRANT_POD_FQDN_LIST" "$min_lexicographical_pod_name")
  if is_empty "$min_lexicographical_pod_fqdn"; then
    echo "Error: Failed to get pod: $min_lexicographical_pod_name fqdn from pod fqdn list: $QDRANT_POD_FQDN_LIST. Exiting." >&2
    return 1
  fi
  echo $min_lexicographical_pod_fqdn
  return 0
}

load_common_library
current_pod_fqdn=$(get_target_pod_fqdn_from_pod_fqdn_vars "$QDRANT_POD_FQDN_LIST" "$CURRENT_POD_NAME")
boostrap_node_fqdn=$(get_boostrap_node)

# TLS setup
if [ "${TLS_ENABLED:-}" = "true" ]; then
  SCHEME="https"
  CURL_TLS="-k"
else
  SCHEME="http"
  CURL_TLS=""
fi

if [ "$current_pod_fqdn" == "$boostrap_node_fqdn" ]; then
  exec ./qdrant --uri "${SCHEME}://${current_pod_fqdn}:6335"
else
  echo "BOOTSTRAP_HOSTNAME: ${boostrap_node_fqdn}"
  QDRANT_CURL_BIN=./tools/curl
  until qdrant_curl ${SCHEME}://${boostrap_node_fqdn}:6333/cluster; do
    echo "INFO: wait for bootstrap node starting..."
    sleep 1;
  done
  exec ./qdrant --bootstrap "${SCHEME}://${boostrap_node_fqdn}:6335" --uri "${SCHEME}://${current_pod_fqdn}:6335"
fi
