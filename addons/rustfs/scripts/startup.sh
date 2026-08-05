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

# Mirrors RustFS 1.0.0-beta.8 (64c0ede) parity selection
# in crates/ecstore/src/config/storageclass.rs.
# Re-verify on: engine version upgrade, #4801 merge, parity algorithm change.
default_parity_count() {
  local drives=$1
  case $drives in
    1) echo 0 ;;
    2|3) echo 1 ;;
    4|5) echo 2 ;;
    6|7) echo 3 ;;
    *) echo 4 ;;
  esac
}

parse_nonnegative_decimal() {
  local value=$1
  local name=$2
  local original=$value
  case "$value" in
    +*) value=${value#+} ;;
  esac
  case "$value" in
    ''|*[!0-9]*)
      echo "FATAL: $name must be a non-negative decimal integer, got '$original'." >&2
      return 1
      ;;
  esac

  while [ "${value#0}" != "$value" ]; do
    value=${value#0}
  done
  value=${value:-0}

  if [ "${#value}" -gt 20 ]; then
    echo "FATAL: $name is outside the supported 64-bit unsigned integer range, got '$original'." >&2
    return 1
  fi
  if [ "${#value}" -eq 20 ]; then
    local first_digit
    local remaining_digits
    first_digit=${value%"${value#?}"}
    remaining_digits=${value#?}
    if [ "$first_digit" != "1" ] || [ "$remaining_digits" -gt 8446744073709551615 ]; then
      echo "FATAL: $name is outside the supported 64-bit unsigned integer range, got '$original'." >&2
      return 1
    fi
  fi
  echo "$value"
}

configured_set_drive_count() {
  if [ "${RUSTFS_ERASURE_SET_DRIVE_COUNT+x}" != "x" ]; then
    # RustFS uses 0 as the explicit automatic-layout sentinel when unset.
    echo 0
    return 0
  fi
  parse_nonnegative_decimal "$RUSTFS_ERASURE_SET_DRIVE_COUNT" "RUSTFS_ERASURE_SET_DRIVE_COUNT"
}

# Mirrors lookup_config() and parse_storage_class() in the same beta.8
# storageclass.rs: empty selects the default; non-empty must be EC:<parity>.
standard_parity_count() {
  local set_size=$1
  local storage_class
  storage_class=${RUSTFS_STORAGE_CLASS_STANDARD-}
  if [ -z "$storage_class" ]; then
    default_parity_count "$set_size"
    return 0
  fi

  case "$storage_class" in
    EC:*) ;;
    *)
      echo "FATAL: RUSTFS_STORAGE_CLASS_STANDARD has unsupported format '$storage_class'; expected EC:<parity>." >&2
      return 1
      ;;
  esac

  local parity
  parity=$(parse_nonnegative_decimal "${storage_class#EC:}" "RUSTFS_STORAGE_CLASS_STANDARD parity") || return 1
  local max_parity
  max_parity=$((set_size / 2))
  case "$parity" in
    0|1|2|3|4|5|6|7|8)
      if [ "$parity" -gt "$max_parity" ]; then
        echo "FATAL: RUSTFS_STORAGE_CLASS_STANDARD parity $parity should be less than or equal to $max_parity for drives_per_set=$set_size." >&2
        return 1
      fi
      ;;
    *)
      echo "FATAL: RUSTFS_STORAGE_CLASS_STANDARD parity $parity should be less than or equal to $max_parity for drives_per_set=$set_size." >&2
      return 1
      ;;
  esac
  echo "$parity"
}

# Mirrors RustFS 1.0.0-beta.8 (64c0ede) DisksLayout::new() and
# common_set_drive_count() in crates/ecstore/src/disks_layout.rs.
# Re-verify on: engine version upgrade, #4801 merge, SET_SIZES range change.
drives_per_set() {
  local pool_size=$1
  local configured
  configured=$(configured_set_drive_count) || return 1

  if [ "$pool_size" -eq 1 ]; then
    echo 1
    return 0
  fi

  case "$configured" in
    0) ;;
    2|3|4|5|6|7|8|9|10|11|12|13|14|15|16)
      if [ $((pool_size % configured)) -ne 0 ]; then
        echo "FATAL: pool has $pool_size drives but RUSTFS_ERASURE_SET_DRIVE_COUNT=$configured is not a supported divisor in [2,16]." >&2
        echo 0
        return 1
      fi
      echo "$configured"
      return 0
      ;;
    *)
      echo "FATAL: pool has $pool_size drives but RUSTFS_ERASURE_SET_DRIVE_COUNT=$configured is not a supported divisor in [2,16]." >&2
      echo 0
      return 1
      ;;
  esac

  if [ "$pool_size" -le 16 ]; then
    echo "$pool_size"
    return 0
  fi
  local d=16
  while [ $d -ge 2 ]; do
    if [ $((pool_size % d)) -eq 0 ]; then
      echo "$d"
      return 0
    fi
    d=$((d - 1))
  done
  echo "FATAL: pool has $pool_size drives which is not divisible by any erasure set size in [2,16]." >&2
  echo 0
  return 1
}

validate_pool_sizes() {
  local replicas=$1
  local prev=0
  local first_pool_parity=""
  local pool_index=0
  local old_ifs="$IFS"
  IFS=','
  for cur in $replicas; do
    local pool_size=$((cur - prev))
    local set_size
    set_size=$(drives_per_set "$pool_size") || {
      IFS="$old_ifs"
      return 1
    }
    if [ $pool_index -eq 0 ]; then
      first_pool_parity=$(standard_parity_count "$set_size") || {
        IFS="$old_ifs"
        return 1
      }
    fi
    if [ "$set_size" -le "$first_pool_parity" ]; then
      echo "FATAL: erasure pool $pool_index has drives_per_set=$set_size but inherited parity is $first_pool_parity (from pool 0)." >&2
      echo "data_blocks would be $((set_size - first_pool_parity)) which causes TooFewDataShards panic." >&2
      echo "Scale to a replica count where every pool's erasure set has at least $((first_pool_parity + 1)) drives." >&2
      IFS="$old_ifs"
      return 1
    fi
    prev=$cur
    pool_index=$((pool_index + 1))
  done
  IFS="$old_ifs"
  return 0
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

  if ! validate_pool_sizes "$replicas"; then
    exit 1
  fi

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
