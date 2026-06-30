#!/bin/sh

replicas_history_file="/rustfs-config/RUSTFS_REPLICAS_HISTORY"
writable_certs_path="/data/.rustfs/certs"

setup_tls_certs() {
  if [ "${TLS_ENABLED:-}" = "true" ]; then
    echo "Setting up TLS certificates for RustFS..."

    for cert_file in ca.crt tls.crt tls.key; do
      if [ ! -r "${CERTS_PATH}/${cert_file}" ]; then
        echo "TLS certificate source file is missing or unreadable: ${CERTS_PATH}/${cert_file}" >&2
        exit 1
      fi
    done

    mkdir -p "${writable_certs_path}" || {
      echo "Failed to create writable TLS certificate directory: ${writable_certs_path}" >&2
      exit 1
    }

    cp -L "${CERTS_PATH}/tls.crt" "${writable_certs_path}/rustfs_cert.pem" || exit 1
    cp -L "${CERTS_PATH}/tls.key" "${writable_certs_path}/rustfs_key.pem" || exit 1
    cp -L "${CERTS_PATH}/ca.crt" "${writable_certs_path}/ca.crt" || exit 1

    chmod 0644 "${writable_certs_path}/rustfs_cert.pem" "${writable_certs_path}/ca.crt" || exit 1
    chmod 0600 "${writable_certs_path}/rustfs_key.pem" || exit 1

    for cert_file in rustfs_cert.pem rustfs_key.pem ca.crt; do
      if [ ! -s "${writable_certs_path}/${cert_file}" ]; then
        echo "TLS certificate target file is missing or empty: ${writable_certs_path}/${cert_file}" >&2
        exit 1
      fi
    done

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
    local base="$RUSTFS_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${RUSTFS_API_PORT}/data"
    if [ $prev -eq $((cur - 1)) ]; then
      volumes="$volumes $protocol://$RUSTFS_COMPONENT_NAME-${prev}.${base}"
    else
      volumes="$volumes $protocol://$RUSTFS_COMPONENT_NAME-{${prev}...$((cur-1))}.${base}"
    fi
    prev=$cur
  done
  IFS="$old_ifs"
  echo "$volumes"
}

wait_for_peers_dns() {
  local headless="$RUSTFS_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN"
  local replicas_count=$1
  local i=0
  echo "Waiting for all peer DNS records to resolve ($replicas_count peers)..."
  while [ $i -lt $replicas_count ]; do
    local peer="$RUSTFS_COMPONENT_NAME-${i}.${headless}"
    local attempts=0
    while ! getent hosts "$peer" >/dev/null 2>&1; do
      attempts=$((attempts + 1))
      if [ $((attempts % 10)) -eq 0 ]; then
        echo "Still waiting for DNS: $peer (attempt $attempts)..."
      fi
      sleep 2
    done
    i=$((i + 1))
  done
  echo "All peer DNS records resolved."
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
    RUSTFS_VOLUMES="/data"
  else
    # Distributed mode: generate volume endpoints
    RUSTFS_VOLUMES=$(generate_volumes_env "$replicas")
    echo "RustFS distributed volumes: $RUSTFS_VOLUMES"

    # Wait for all peer DNS records before starting (chicken-and-egg with StatefulSet sequential creation)
    local last_replica
    local old_ifs="$IFS"
    IFS=','
    for last_replica in $replicas; do :; done
    IFS="$old_ifs"
    wait_for_peers_dns "$last_replica"
  fi

  echo "Starting RustFS server (volumes=$RUSTFS_VOLUMES)"
  exec /usr/bin/rustfs $RUSTFS_VOLUMES
}

# This is magic for shellspec ut framework.
${__SOURCED__:+false} : || return 0

# main
startup
