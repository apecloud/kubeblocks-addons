#!/bin/bash
# shellcheck disable=SC2016 # jq expressions deliberately use literal $variables.

storage_class_error() {
  echo "MINIO_STORAGE_CLASS_ERROR: $1" >&2
  return 1
}

minio_mc() {
  timeout 15 mc --config-dir "$mc_config_dir" "$@" 2>/dev/null
}

read_storage_class() {
  local output
  output=$(minio_mc --json admin config get policy storage_class) || {
    storage_class_error 'cannot read native configuration'; return 1;
  }
  output=$("$jq_bin" -ce '[.config[] | select(.subSystem == "storage_class") | .kv[] | select(.key == "standard" or .key == "rrs")] | from_entries | select(has("standard") and has("rrs")) | select(all(.[]; type == "string" and test("^(EC:[0-8])?$")))' <<< "$output") || {
    storage_class_error 'unexpected native configuration'; return 1;
  }
  native_standard=$("$jq_bin" -r .standard <<< "$output")
  native_rrs=$("$jq_bin" -r .rrs <<< "$output")
}

validate_storage_class() {
  local size first_set_size=${set_sizes[0]}
  # MinIO's global storage class is initialized from the first pool.
  if [[ -n "$desired_standard" ]]; then
    standard_parity=${desired_standard#EC:}
  elif (( first_set_size >= 8 )); then
    standard_parity=4
  else
    standard_parity=$((first_set_size / 2))
  fi
  rrs_parity=${desired_rrs#EC:}
  if [[ -z "$rrs_parity" ]]; then
    rrs_parity=1
    (( first_set_size == 1 )) && rrs_parity=0
  fi
  for size in "${set_sizes[@]}"; do
    if (( standard_parity > size / 2 || rrs_parity > size / 2 )); then
      storage_class_error "parity exceeds half of an erasure set of $size drives"; return 1
    fi
    if (( standard_parity > 0 && rrs_parity > 0 && standard_parity < rrs_parity )); then
      storage_class_error 'STANDARD parity must not be below RRS parity when both are nonzero'; return 1
    fi
  done
}

apply_storage_class() (
  local desired_file=${1:-${MINIO_STORAGE_CLASS_FILE:-/minio-storage-class/storage-class.json}}
  local jq_bin=${MINIO_JQ:-/kb-tools/jq}
  local desired info sizes node endpoint standard_parity rrs_parity native_standard native_rrs
  desired=$("$jq_bin" -cse '
    select(length == 1) | .[0] | select(type == "object" and all(to_entries[];
      (.key == "standard" or .key == "rrs") and (.value | type == "string" and test("^(EC:[0-8])?$"))))' "$desired_file") || {
    storage_class_error 'invalid desired configuration'; return 1;
  }
  # The initial template leaves empty classes at their native defaults. During
  # reload an explicitly changed empty value restores that class to its default.
  if [[ "$desired_file" != - ]]; then
    desired=$("$jq_bin" -c 'with_entries(select(.value != ""))' <<< "$desired") || return 1
  fi
  [[ "$desired" != '{}' ]] || return 0
  [[ "${MINIO_COMP_REPLICAS:-}" =~ ^[1-9][0-9]*$ ]] || {
    storage_class_error 'missing replica count'; return 1;
  }
  if [[ -n "${MINIO_STORAGE_CLASS_STANDARD+x}" || -n "${MINIO_STORAGE_CLASS_RRS+x}" ]]; then
    storage_class_error 'remove storage class environment overrides before using dynamic configuration'; return 1
  fi
  local mc_config_dir protocol=http
  mc_config_dir=$(mktemp -d) || return 1
  trap 'rm -rf "$mc_config_dir"' EXIT
  if [[ "${TLS_ENABLED:-false}" == true ]]; then
    protocol=https
    mkdir -p "$mc_config_dir/certs/CAs"
    cp "${MINIO_CA_FILE:-/kb-tools/minio-ca.crt}" "$mc_config_dir/certs/CAs/ca.crt" 2>/dev/null || {
      storage_class_error 'cannot load MinIO CA certificate'; return 1;
    }
  fi
  minio_mc alias set policy "$protocol://${HOSTNAME}.$MINIO_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${MINIO_API_PORT:-9000}" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null || {
    storage_class_error 'cannot connect to MinIO'; return 1;
  }
  read_storage_class || return 1
  local desired_standard desired_rrs
  desired_standard=$("$jq_bin" -r --arg current "$native_standard" 'if has("standard") then .standard else $current end' <<< "$desired") || return 1
  desired_rrs=$("$jq_bin" -r --arg current "$native_rrs" 'if has("rrs") then .rrs else $current end' <<< "$desired") || return 1
  info=$(minio_mc --json admin info policy) || {
    storage_class_error 'cannot read erasure set geometry'; return 1;
  }
  sizes=$("$jq_bin" -er '.info.backend.totalDrivesPerSet | select(type == "array" and length > 0 and all(.[]; type == "number" and . >= 1 and . <= 16 and floor == .)) | .[]' <<< "$info") || {
    storage_class_error 'missing or invalid erasure set geometry'; return 1;
  }
  local -a set_sizes
  while IFS= read -r size; do set_sizes+=("$size"); done <<< "$sizes"
  validate_storage_class || return 1
  minio_mc admin config set policy storage_class "standard=$desired_standard" "rrs=$desired_rrs" >/dev/null || {
    storage_class_error 'native configuration update failed'; return 1;
  }
  # Read each server directly: a persisted config alone does not prove live reload.
  for ((node=0; node<MINIO_COMP_REPLICAS; node++)); do
    endpoint="$protocol://$MINIO_COMPONENT_NAME-$node.$MINIO_COMPONENT_NAME-headless.$CLUSTER_NAMESPACE.svc.$CLUSTER_DOMAIN:${MINIO_API_PORT:-9000}"
    minio_mc alias set policy "$endpoint" "$MINIO_ROOT_USER" "$MINIO_ROOT_PASSWORD" >/dev/null || {
      storage_class_error "cannot connect to server $node"; return 1;
    }
    read_storage_class || return 1
    [[ "$native_standard" == "$desired_standard" && "$native_rrs" == "$desired_rrs" ]] || {
      storage_class_error "native configuration mismatch on server $node"; return 1;
    }
    info=$(minio_mc --json admin info policy) || {
      storage_class_error "cannot read runtime policy on server $node"; return 1;
    }
    "$jq_bin" -e --argjson standard "$standard_parity" --argjson rrs "$rrs_parity" '.info.backend | .standardSCParity == $standard and .rrSCParity == $rrs' <<< "$info" >/dev/null || {
      storage_class_error "runtime policy mismatch on server $node"; return 1;
    }
  done
)

${__SOURCED__:+false} : || return 0
apply_storage_class "$@"
