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

mkdir -p "${DATA_DIR}"

# Safety check: refuse to restore into a non-empty data directory.
# Use -maxdepth 1 to check for any real data entry directly inside DATA_DIR.
placeholder="${DATA_DIR}/.kb-data-protection"
unexpected_entries=$(find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name ".kb-data-protection" ! -name "lost+found")
if [ -n "${unexpected_entries}" ]; then
  echo "ERROR: ${DATA_DIR} is not empty. Remove all data before restoring." >&2
  exit 1
fi
if [ -e "${placeholder}" ] && [ ! -f "${placeholder}" ]; then
  echo "ERROR: ${placeholder} exists but is not a file." >&2
  exit 1
fi
touch "${placeholder}"

archive="${DP_BACKUP_NAME}.tar.zst"
if datasafed list "${archive}" 2>/dev/null | grep -qF "${archive}"; then
  echo "INFO: Restoring from ${archive}..."
  datasafed pull -d zstd-fastest "${archive}" - | tar -xvf - -C "${DATA_DIR}"
else
  echo "ERROR: backup archive '${archive}' not found in repository." >&2
  exit 1
fi

seed_multipart_aof_from_rdb() {
  local rdb="${DATA_DIR}/dump.rdb"
  local append_dirname="${VALKEY_APPEND_DIRNAME:-appendonlydir}"
  local append_filename="${VALKEY_APPEND_FILENAME:-appendonly.aof}"
  local append_dir="${DATA_DIR}/${append_dirname}"
  local base_file="${append_dir}/${append_filename}.1.base.rdb"
  local incr_file="${append_dir}/${append_filename}.1.incr.aof"
  local manifest_file="${append_dir}/${append_filename}.manifest"
  local restored_aof_state=""

  if [ ! -s "${rdb}" ]; then
    echo "ERROR: restored archive must contain a non-empty dump.rdb." >&2
    exit 1
  fi

  restored_aof_state=$(find "${DATA_DIR}" -mindepth 1 \( \
    -name "${append_dirname}" -o \
    -name "${append_filename}" -o \
    -name "${append_filename}.*" -o \
    -name "*.aof" \
  \) -print -quit)
  if [ -n "${restored_aof_state}" ]; then
    echo "ERROR: restored archive already contains AOF state at ${restored_aof_state}; refusing to synthesize AOF from dump.rdb." >&2
    exit 1
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

# Cluster (sharding) restore guard: v1 supports SAME shard count only —
# keys restored onto a shard that does not own their hash slots are
# silently unreachable, so a mismatch must stop before the pod starts.
# Enforcement is engine-truth (cluster-meta embedded at backup time)
# compared against RESTORE_TARGET_SHARDS when the operator provides it
# via dataprotection.kubeblocks.io/restore-env; without the env we can
# only warn (DP jobs cannot see target sharding vars — platform gap,
# kubeblocks#10540).
verify_cluster_shard_count() {
  local meta="${DATA_DIR}/cluster-meta" source_shards
  [ -f "${meta}" ] || return 0
  source_shards=$(grep '^source_shards=' "${meta}" | cut -d= -f2)
  rm -f "${meta}"   # metadata, not engine data — never leave it in DATA_DIR
  case "${source_shards}" in
    ''|*[!0-9]*)
      echo "ERROR: cluster-meta present but source_shards is invalid ('${source_shards}')." >&2
      exit 1 ;;
  esac
  if [ -n "${RESTORE_TARGET_SHARDS:-}" ]; then
    if [ "${RESTORE_TARGET_SHARDS}" != "${source_shards}" ]; then
      echo "ERROR: shard count mismatch — backup taken from ${source_shards} shard(s), target declares ${RESTORE_TARGET_SHARDS}. v1 cluster restore requires the SAME shard count; refusing before any pod starts." >&2
      exit 1
    fi
    echo "INFO: cluster restore shard count verified (${source_shards})."
  else
    echo "WARNING: cluster backup (source_shards=${source_shards}) restored without RESTORE_TARGET_SHARDS — same-shard-count is the operator's responsibility; set it via restore-env to enforce."
  fi
}

verify_cluster_shard_count

seed_multipart_aof_from_rdb

rm -f "${placeholder}" && sync
echo "INFO: Restore complete."
