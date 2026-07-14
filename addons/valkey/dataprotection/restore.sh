#!/bin/bash
# restore.sh — prepareData phase: extract backup archive into DATA_DIR.
#
# Runs as an init container before the Valkey pod starts.
# DATA_DIR must be empty (or contain only the .kb-data-protection placeholder)
# to prevent accidentally overwriting a running cluster.

set -e
set -o pipefail

[ -n "${DP_DATASAFED_BIN_PATH}" ] && export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

case "${DATA_DIR:-}" in
  /*) ;;
  *) echo "ERROR: DATA_DIR must be an existing canonical absolute directory." >&2; exit 1 ;;
esac
[ "${DATA_DIR}" != "/" ] && [ -d "${DATA_DIR}" ] && [ ! -L "${DATA_DIR}" ] || {
  echo "ERROR: DATA_DIR must be an existing canonical non-root directory." >&2
  exit 1
}
canonical_data_dir=$(cd -P "${DATA_DIR}" 2>/dev/null && pwd -P) || exit 1
[ "${canonical_data_dir}" = "${DATA_DIR}" ] || {
  echo "ERROR: DATA_DIR must not contain symlink or dot-segment aliases." >&2
  exit 1
}
case "${VALKEY_APPEND_DIRNAME-appendonlydir}" in
  ''|*/*|.|..) echo "ERROR: unsafe VALKEY_APPEND_DIRNAME for restore." >&2; exit 1 ;;
esac
case "${VALKEY_APPEND_FILENAME-appendonly.aof}" in
  ''|*/*|.|..) echo "ERROR: unsafe VALKEY_APPEND_FILENAME for restore." >&2; exit 1 ;;
esac

cleanup_restored_payload() {
  find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name ".kb-data-protection" ! -name "lost+found" -exec rm -rf {} +
}

# Safety check: refuse to restore into a non-empty data directory.
# Use -maxdepth 1 to check for any real data entry directly inside DATA_DIR.
placeholder="${DATA_DIR}/.kb-data-protection"
unexpected_entries=$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name ".kb-data-protection" ! -name "lost+found")
if [ -n "${unexpected_entries}" ]; then
  echo "ERROR: ${DATA_DIR} is not empty. Remove all data before restoring." >&2
  exit 1
fi
if [ -e "${placeholder}" ] || [ -L "${placeholder}" ]; then
  [ -f "${placeholder}" ] && [ ! -L "${placeholder}" ] || {
    echo "ERROR: ${placeholder} is not a safe regular file." >&2
    exit 1
  }
else
  touch "${placeholder}"
fi

archive="${DP_BACKUP_NAME}.tar.zst"
if datasafed list "${archive}" 2>/dev/null | grep -qF "${archive}"; then
  echo "INFO: Restoring from ${archive}..."
  if ! datasafed pull -d zstd-fastest "${archive}" - | tar -xvf - -C "${DATA_DIR}"; then
    echo "ERROR: restore archive extraction failed; removing partial payload." >&2
    cleanup_restored_payload
    exit 1
  fi
else
  echo "ERROR: backup archive '${archive}' not found in repository." >&2
  exit 1
fi

seed_multipart_aof_from_rdb() {
  local rdb="${DATA_DIR}/dump.rdb"
  local append_dirname="${VALKEY_APPEND_DIRNAME-appendonlydir}"
  local append_filename="${VALKEY_APPEND_FILENAME-appendonly.aof}"
  local append_dir="${DATA_DIR}/${append_dirname}"
  local base_file="${append_dir}/${append_filename}.1.base.rdb"
  local incr_file="${append_dir}/${append_filename}.1.incr.aof"
  local manifest_file="${append_dir}/${append_filename}.manifest"
  local restored_aof_state=""

  if [ ! -f "${rdb}" ] || [ -L "${rdb}" ] || [ ! -s "${rdb}" ]; then
    echo "ERROR: restored archive must contain a safe regular non-empty dump.rdb." >&2
    return 1
  fi

  restored_aof_state=$(find "${DATA_DIR}" -mindepth 1 \( \
    -name "${append_dirname}" -o \
    -name "${append_filename}" -o \
    -name "${append_filename}.*" -o \
    -name "*.aof" \
  \) -print -quit)
  if [ -n "${restored_aof_state}" ]; then
    echo "ERROR: restored archive already contains AOF state at ${restored_aof_state}; refusing to synthesize AOF from dump.rdb." >&2
    return 1
  fi

  mkdir -p "${append_dir}"
  cp "${rdb}" "${base_file}"
  : > "${incr_file}"
  {
    printf 'file %s seq 1 type b\n' "$(basename "${base_file}")"
    printf 'file %s seq 1 type i\n' "$(basename "${incr_file}")"
  } > "${manifest_file}"
  echo "INFO: Seeded multipart AOF manifest from restored dump.rdb."
}

validate_restore_slot_ranges() {
  awk -v raw="$1" 'BEGIN {
    if (raw == "") exit 1
    n = split(raw, parts, ",")
    for (i = 1; i <= n; i++) {
      token = parts[i]
      if (token ~ /^[0-9]+$/) {
        start = token + 0; end = start
      } else if (token ~ /^[0-9]+-[0-9]+$/) {
        split(token, bounds, "-")
        start = bounds[1] + 0; end = bounds[2] + 0
      } else {
        exit 1
      }
      if (start < 0 || end > 16383 || start > end) exit 1
      for (slot = start; slot <= end; slot++) {
        if (seen[slot]++) exit 1
      }
    }
  }'
}

validate_cluster_restore_meta() {
  local meta="$1" source_shards shard_master_id shard_slot_ranges rdb_sha256 actual_rdb_sha256
  local source_count master_count ranges_count digest_count

  source_count=$(grep -c '^source_shards=' "${meta}" || true)
  master_count=$(grep -c '^shard_master_id=' "${meta}" || true)
  ranges_count=$(grep -c '^shard_slot_ranges=' "${meta}" || true)
  digest_count=$(grep -c '^rdb_sha256=' "${meta}" || true)
  if [ "${source_count}" -ne 1 ]; then
    echo "ERROR: cluster-meta must contain exactly one source_shards entry." >&2
    return 1
  fi
  if [ "${master_count}" -ne 1 ]; then
    echo "ERROR: cluster-meta missing shard_master_id or contains duplicates." >&2
    return 1
  fi
  if [ "${ranges_count}" -ne 1 ]; then
    echo "ERROR: cluster-meta missing shard_slot_ranges or contains duplicates." >&2
    return 1
  fi
  if [ "${digest_count}" -ne 1 ]; then
    echo "ERROR: cluster-meta missing rdb_sha256 or contains duplicates." >&2
    return 1
  fi

  source_shards=$(grep '^source_shards=' "${meta}" | cut -d= -f2-)
  shard_master_id=$(grep '^shard_master_id=' "${meta}" | cut -d= -f2-)
  shard_slot_ranges=$(grep '^shard_slot_ranges=' "${meta}" | cut -d= -f2-)
  rdb_sha256=$(grep '^rdb_sha256=' "${meta}" | cut -d= -f2-)
  case "${source_shards}" in ''|*[!0-9]*)
    echo "ERROR: invalid source_shards '${source_shards}' in cluster-meta." >&2
    return 1 ;;
  esac
  if [ "${source_shards}" -lt 3 ] || [ "${source_shards}" -gt 32 ]; then
    echo "ERROR: source_shards ${source_shards} is outside supported range 3..32." >&2
    return 1
  fi
  case "${shard_master_id}" in ''|*[!A-Za-z0-9]*)
    echo "ERROR: invalid shard_master_id in cluster-meta." >&2
    return 1 ;;
  esac
  if ! validate_restore_slot_ranges "${shard_slot_ranges}"; then
    echo "ERROR: invalid shard_slot_ranges '${shard_slot_ranges}' in cluster-meta." >&2
    return 1
  fi
  case "${rdb_sha256}" in ''|*[!0-9a-fA-F]*)
    echo "ERROR: invalid rdb_sha256 in cluster-meta." >&2
    return 1 ;;
  esac
  if [ "${#rdb_sha256}" -ne 64 ]; then
    echo "ERROR: invalid rdb_sha256 length in cluster-meta." >&2
    return 1
  fi
  actual_rdb_sha256=$(sha256sum "${DATA_DIR}/dump.rdb" 2>/dev/null | awk '{print $1}')
  if [ "${actual_rdb_sha256}" != "${rdb_sha256}" ]; then
    echo "ERROR: restored dump.rdb does not match cluster-meta rdb_sha256." >&2
    return 1
  fi
  echo "INFO: Validated cluster restore metadata (source_shards=${source_shards}, shard_slot_ranges=${shard_slot_ranges})."
}

cluster_meta="${DATA_DIR}/cluster-meta"
if [ -e "${cluster_meta}" ] || [ -L "${cluster_meta}" ]; then
  if [ ! -f "${cluster_meta}" ] || [ -L "${cluster_meta}" ]; then
    echo "ERROR: restored cluster-meta is not a safe regular file." >&2
    cleanup_restored_payload
    exit 1
  fi
  if ! validate_cluster_restore_meta "${cluster_meta}"; then
    cleanup_restored_payload
    exit 1
  fi
fi

if ! seed_multipart_aof_from_rdb; then
  cleanup_restored_payload
  exit 1
fi

if [ -f "${cluster_meta}" ]; then
  restore_state="${DATA_DIR}/.kb-cluster-restore-state"
  restore_state_tmp=$(mktemp "${restore_state}.tmp.XXXXXX") || {
    echo "ERROR: cannot allocate cluster restore intent file." >&2
    cleanup_restored_payload
    exit 1
  }
  cluster_meta_sha256=$(sha256sum "${cluster_meta}" 2>/dev/null | awk '{print $1}')
  if [ "${#cluster_meta_sha256}" -ne 64 ] || \
     ! printf 'phase=prepared\nmeta_sha256=%s\n' "${cluster_meta_sha256}" > "${restore_state_tmp}" || \
     ! mv -f "${restore_state_tmp}" "${restore_state}" || ! sync; then
    rm -f "${restore_state_tmp}"
    echo "ERROR: cannot persist cluster restore intent." >&2
    cleanup_restored_payload
    exit 1
  fi
fi

rm -f "${placeholder}" && sync
echo "INFO: Restore complete."
