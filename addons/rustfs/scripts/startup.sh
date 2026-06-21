#!/bin/sh

replicas_history_file="/rustfs-config/RUSTFS_REPLICAS_HISTORY"
writable_certs_path="/data/.rustfs/certs"

setup_tls_certs() {
  if [ "$TLS_ENABLED" = "true" ] && [ -f ${CERTS_PATH}/ca.crt ]; then
    echo "Setting up TLS certificates for RustFS..."

    mkdir -p ${writable_certs_path}

    cp -L ${CERTS_PATH}/tls.crt ${writable_certs_path}/tls.crt
    cp -L ${CERTS_PATH}/tls.key ${writable_certs_path}/tls.key
    cp -L ${CERTS_PATH}/ca.crt ${writable_certs_path}/ca.crt

    chmod 600 ${writable_certs_path}/tls.key

    export RUSTFS_TLS_PATH=${writable_certs_path}

    echo "TLS certificates setup completed at ${writable_certs_path}"
  fi
}

init_buckets() {
  local buckets=$1
  local old_ifs="$IFS"
  IFS=','
  for bucket in $buckets; do
    directory="/data/$bucket"
    if mkdir -p "$directory"; then
      echo "Successfully init bucket: $directory"
    else
      echo "Failed to init bucket: $directory"
    fi
  done
  IFS="$old_ifs"
}

read_replicas_history() {
  local file=$1
  content=$(cat "$file")
  content=$(echo "$content" | tr -d '[]')
  echo "$content"
}

generate_volumes_env() {
  local replicas=$1
  local volumes=""
  local protocol="http"

  if [ "$TLS_ENABLED" = "true" ]; then
    protocol="https"
  fi

  prev=0
  local old_ifs="$IFS"
  IFS=','
  for cur in $replicas; do
    if [ $prev -eq 0 ]; then
      volumes="$volumes $protocol://$RUSTFS_COMPONENT_NAME-{0...$((cur-1))}.$RUSTFS_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${RUSTFS_API_PORT}/data"
    else
      volumes="$volumes $protocol://$RUSTFS_COMPONENT_NAME-{$prev...$((cur-1))}.$RUSTFS_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${RUSTFS_API_PORT}/data"
    fi
    prev=$cur
  done
  IFS="$old_ifs"
  echo "$volumes"
}

startup() {
  if [ ! -f "$replicas_history_file" ]; then
    echo "rustfs config doesn't exist" >&2
    exit 1
  fi

  setup_tls_certs

  buckets="$RUSTFS_BUCKETS"
  if [ -n "$buckets" ]; then
    init_buckets "$buckets"
  fi

  replicas=$(read_replicas_history "$replicas_history_file")
  echo "the rustfs replicas history is $replicas"

  # Single node mode: use local data path
  if [ "$replicas" = "1" ]; then
    export RUSTFS_VOLUMES="/data"
  else
    # Distributed mode: generate volume endpoints
    volumes=$(generate_volumes_env "$replicas")
    export RUSTFS_VOLUMES="$volumes"
    echo "RustFS distributed volumes: $RUSTFS_VOLUMES"
  fi

  # RUSTFS_ADDRESS and RUSTFS_CONSOLE_ADDRESS are already set via container env
  echo "Starting RustFS server (RUSTFS_VOLUMES=$RUSTFS_VOLUMES)"
  exec /app/rustfs
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

# main
startup
