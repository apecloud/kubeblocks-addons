#!/bin/bash

replicas_history_file="/rustfs-config/RUSTFS_REPLICAS_HISTORY"
data_dir="/data"
writable_certs_path="/data/.rustfs/certs"

setup_tls_certs() {
  if [ "$TLS_ENABLED" = "true" ] && [ -f ${CERTS_PATH}/ca.crt ]; then
    echo "Setting up TLS certificates for RustFS..."

    mkdir -p ${writable_certs_path}/CAs

    cp -L ${CERTS_PATH}/tls.crt ${writable_certs_path}/tls.crt
    cp -L ${CERTS_PATH}/tls.key ${writable_certs_path}/tls.key
    cp -L ${CERTS_PATH}/ca.crt ${writable_certs_path}/CAs/ca.crt

    chmod 600 ${writable_certs_path}/tls.key

    export RUSTFS_TLS_PATH=${writable_certs_path}

    echo "TLS certificates setup completed at ${writable_certs_path}"
  fi
}

init_buckets() {
  local buckets=$1
  IFS=',' read -ra BUCKET_ARRAY <<< "$buckets"
  for bucket in "${BUCKET_ARRAY[@]}"; do
    directory="$data_dir/$bucket"
    if mkdir -p "$directory"; then
      echo "Successfully init bucket: $directory"
    else
      echo "Failed to init bucket: $directory"
    fi
  done
}

read_replicas_history() {
  local file=$1
  content=$(cat "$file")
  content=$(echo "$content" | tr -d '[]')
  echo "$content"
}

generate_server_pool() {
  local replicas=$1
  local server=""
  prev=0
  IFS=',' read -ra REPLICAS_INDEX_ARRAY <<< "$replicas"
  for cur in "${REPLICAS_INDEX_ARRAY[@]}"; do
    if [ $prev -eq 0 ]; then
      server+=" $HTTP_PROTOCOL://$RUSTFS_COMPONENT_NAME-{0...$((cur-1))}.$RUSTFS_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${RUSTFS_API_PORT}/data"
    else
      server+=" $HTTP_PROTOCOL://$RUSTFS_COMPONENT_NAME-{$prev...$((cur-1))}.$RUSTFS_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${RUSTFS_API_PORT}/data"
    fi
    prev=$cur
  done
  echo "$server"
}

build_startup_cmd() {
  if [ ! -f "$replicas_history_file" ]; then
    echo "rustfs config doesn't exist" >&2
    return 1
  fi

  buckets="$RUSTFS_BUCKETS"
  if [ -n "$buckets" ]; then
    init_buckets "$buckets"
  fi

  replicas=$(read_replicas_history "$replicas_history_file")
  echo "the rustfs replicas history is $replicas" >&2

  # Single node mode: just use local data path
  if [ "$replicas" = "1" ]; then
    cmd="/app/rustfs --address :$RUSTFS_API_PORT --console-address :$RUSTFS_CONSOLE_PORT"
    echo "$cmd"
    return 0
  fi

  server=$(generate_server_pool $replicas)
  echo "the rustfs server pool is $server" >&2

  export RUSTFS_VOLUMES="$server"
  cmd="/app/rustfs --address :$RUSTFS_API_PORT --console-address :$RUSTFS_CONSOLE_PORT"
  echo "$cmd"
  return 0
}

startup() {
  if [ "$TLS_ENABLED" = "true" ]; then
    export HTTP_PROTOCOL="https"
  else
    export HTTP_PROTOCOL="http"
  fi

  setup_tls_certs

  cmd=$(build_startup_cmd)
  status=$?
  if [ $status -ne 0 ]; then
    echo "Failed to build startup command" >&2
    exit 1
  fi
  echo "Starting RustFS server with command: $cmd"
  eval "$cmd"
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

# main
startup
