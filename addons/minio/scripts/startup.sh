#!/bin/bash

replicas_history_file="/minio-config/MINIO_REPLICAS_HISTORY"
bucket_dir="/data"
writable_certs_path="/data/.minio/certs"

setup_tls_certs() {
  if [ "$TLS_ENABLED" = "true" ] && [ -f ${CERTS_PATH}/ca.pem ]; then
    echo "Setting up TLS certificates for MinIO..."

    # Create writable certs directory
    mkdir -p ${writable_certs_path}/CAs

    # Copy certificates from read-only mount to writable location
    cp -L ${CERTS_PATH}/public.crt ${writable_certs_path}/public.crt
    cp -L ${CERTS_PATH}/private.key ${writable_certs_path}/private.key
    cp -L ${CERTS_PATH}/ca.pem ${writable_certs_path}/CAs/ca.crt

    # Set proper permissions
    chmod 600 ${writable_certs_path}/private.key

    # Override CERTS_PATH to use writable location
    export CERTS_PATH=${writable_certs_path}

    echo "TLS certificates setup completed at ${writable_certs_path}"
  fi
}

init_buckets() {
  local buckets=$1
  IFS=',' read -ra BUCKET_ARRAY <<< "$buckets"
  for bucket in "${BUCKET_ARRAY[@]}"; do
    directory="$bucket_dir/$bucket"
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
      server+=" $HTTP_PROTOCOL://$MINIO_COMPONENT_NAME-{0...$((cur-1))}.$MINIO_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN/data"
    else
      server+=" $HTTP_PROTOCOL://$MINIO_COMPONENT_NAME-{$prev...$((cur-1))}.$MINIO_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN/data"
    fi
    prev=$cur
  done
  echo "$server"
}

build_startup_cmd() {
  if [ ! -f "$replicas_history_file" ]; then
    echo "minio config don't existed" >&2
    return 1
  fi

  buckets="$MINIO_BUCKETS"
  if [ -n "$buckets" ]; then
    init_buckets "$buckets"
  fi

  replicas=$(read_replicas_history "$replicas_history_file")
  echo "the minio replicas history is $replicas" >&2

  server=$(generate_server_pool $replicas)
  echo "the minio server pool is $server" >&2

  cmd="/usr/bin/docker-entrypoint.sh minio server $server -S $CERTS_PATH --address :$MINIO_API_PORT --console-address :$MINIO_CONSOLE_PORT"
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
  echo "Starting minio server with command: $cmd"
  eval "$cmd"
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
startup
