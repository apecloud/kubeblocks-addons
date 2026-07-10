#!/bin/sh

set -eu

rustfs_fail() {
  echo "ERROR: $*" >&2
  exit 1
}

rustfs_prepare_datasafed() {
  : "${DP_BACKUP_BASE_PATH:?missing DP_BACKUP_BASE_PATH}"
  if [ -n "${DP_DATASAFED_BIN_PATH:-}" ]; then
    export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
  fi
  export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"
}

rustfs_prepare_mc() {
  : "${DP_DB_HOST:?missing DP_DB_HOST}"

  rustfs_access_key="${DP_DB_USER:-${RUSTFS_ACCESS_KEY:-}}"
  rustfs_secret_key="${DP_DB_PASSWORD:-${RUSTFS_SECRET_KEY:-}}"
  [ -n "${rustfs_access_key}" ] || rustfs_fail "missing DP_DB_USER/RUSTFS_ACCESS_KEY"
  [ -n "${rustfs_secret_key}" ] || rustfs_fail "missing DP_DB_PASSWORD/RUSTFS_SECRET_KEY"

  rustfs_port="${DP_DB_PORT:-${RUSTFS_API_PORT:-9000}}"

  export RUSTFS_ALIAS="${RUSTFS_ALIAS:-rustfs}"
  export MC_CONFIG_DIR="${MC_CONFIG_DIR:-/tmp/rustfs-mc}"

  mkdir -p "${MC_CONFIG_DIR}"
  if [ -n "${RUSTFS_SCHEME:-}" ]; then
    if [ "${RUSTFS_SCHEME}" = "https" ]; then
      rustfs_prepare_mc_trust
    fi
    rustfs_configure_mc_alias "${RUSTFS_SCHEME}" "${rustfs_access_key}" "${rustfs_secret_key}" || \
      rustfs_fail "failed to configure RustFS S3 alias with RUSTFS_SCHEME=${RUSTFS_SCHEME}"
    return
  fi

  if rustfs_configure_mc_alias http "${rustfs_access_key}" "${rustfs_secret_key}"; then
    return
  fi
  rustfs_prepare_mc_trust
  if rustfs_configure_mc_alias https "${rustfs_access_key}" "${rustfs_secret_key}"; then
    return
  fi

  rustfs_fail "failed to configure RustFS S3 alias over http or https"
}

rustfs_prepare_mc_trust() {
  rustfs_tls_ca_file="${RUSTFS_TLS_CA_FILE:-}"
  [ -n "${rustfs_tls_ca_file}" ] || \
    rustfs_fail "RUSTFS_TLS_CA_FILE is required for HTTPS"
  [ -e "${rustfs_tls_ca_file}" ] || \
    rustfs_fail "RustFS TLS CA file ${rustfs_tls_ca_file} does not exist"
  [ -r "${rustfs_tls_ca_file}" ] || \
    rustfs_fail "RustFS TLS CA file ${rustfs_tls_ca_file} is not readable"
  [ -s "${rustfs_tls_ca_file}" ] || \
    rustfs_fail "RustFS TLS CA file ${rustfs_tls_ca_file} is empty"

  rustfs_mc_ca_dir="${MC_CONFIG_DIR}/certs/CAs"
  mkdir -p "${rustfs_mc_ca_dir}"
  cp -L "${rustfs_tls_ca_file}" "${rustfs_mc_ca_dir}/rustfs-ca.crt" || \
    rustfs_fail "failed to install RustFS TLS CA into mc trust directory"
  chmod 0644 "${rustfs_mc_ca_dir}/rustfs-ca.crt"
  [ -s "${rustfs_mc_ca_dir}/rustfs-ca.crt" ] || \
    rustfs_fail "installed RustFS TLS CA is empty"
}

rustfs_configure_mc_alias() {
  rustfs_scheme="$1"
  rustfs_access_key="$2"
  rustfs_secret_key="$3"
  rustfs_port="${DP_DB_PORT:-${RUSTFS_API_PORT:-9000}}"
  rustfs_endpoint="${rustfs_scheme}://${DP_DB_HOST}:${rustfs_port}"

  rustfs_mc alias set "${RUSTFS_ALIAS}" "${rustfs_endpoint}" "${rustfs_access_key}" "${rustfs_secret_key}" --api S3v4 >/dev/null 2>&1 || \
    return 1
  rustfs_mc ls "${RUSTFS_ALIAS}/" >/dev/null 2>&1 || \
    return 1

  export RUSTFS_ENDPOINT="${rustfs_endpoint}"
  export RUSTFS_SCHEME_EFFECTIVE="${rustfs_scheme}"
  echo "INFO: RustFS S3 endpoint resolved with scheme=${rustfs_scheme}"
  return 0
}

rustfs_mc() {
  mc --config-dir "${MC_CONFIG_DIR:-/tmp/rustfs-mc}" "$@"
}

rustfs_archive_name() {
  printf '%s\n' "${RUSTFS_BACKUP_PREFIX:-${DP_BACKUP_NAME:?missing DP_BACKUP_NAME}}"
}

rustfs_count_lines() {
  rustfs_count=0
  while IFS= read -r _; do
    rustfs_count=$((rustfs_count + 1))
  done < "$1"
  printf '%s\n' "${rustfs_count}"
}

rustfs_save_backup_size() {
  : "${DP_BACKUP_INFO_FILE:?missing DP_BACKUP_INFO_FILE}"
  total_size=0
  datasafed stat / 2>/dev/null > "${TMPDIR:-/tmp}/rustfs-datasafed-stat.txt" || true
  while IFS=' ' read -r key value _; do
    if [ "${key}" = "TotalSize:" ] && [ -n "${value}" ]; then
      total_size="${value}"
      break
    fi
  done < "${TMPDIR:-/tmp}/rustfs-datasafed-stat.txt"
  printf '{"totalSize":"%s"}' "${total_size}" > "${DP_BACKUP_INFO_FILE}"
}
