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

# Cluster (sharding) restore: NOT SUPPORTED in v1 — fail fast.
#
# Same shard count is NOT a sufficient safety condition (review, PR #3044):
# restore re-forms the cluster (phase B) with an even slot split, but the
# SOURCE layout may differ (any post-rebalance / scale history). Keys
# restored onto a shard that does not own their hash slots are silently
# unreachable, and archive->target-shard positional mapping is itself
# unverified. Until a slot-aware restore is designed (cluster-meta already
# records source_shards + shard_slot_ranges for exactly that), a cluster
# archive is refused outright — refusal beats silent misplacement.
refuse_cluster_restore() {
  local meta="${DATA_DIR}/cluster-meta" source_shards
  [ -f "${meta}" ] || return 0
  source_shards=$(grep '^source_shards=' "${meta}" | cut -d= -f2)
  # Remove everything THIS run extracted before exiting: the emptiness
  # guard proved DATA_DIR held no user data at entry, so all entries here
  # are our own extraction output. Without this, a retried prepareData
  # pod trips the '/data is not empty' guard over our leftovers and the
  # TRUE refusal reason is masked on every retry (live finding, CT11
  # focused rerun).
  find "${DATA_DIR}" -mindepth 1 -maxdepth 1 ! -name ".kb-data-protection" ! -name "lost+found" -exec rm -rf {} +
  echo "ERROR: this archive is a Valkey CLUSTER (sharding) backup (source_shards=${source_shards})." >&2
  echo "  Cluster datafile restore is NOT supported in v1: restored slot layouts cannot yet be" >&2
  echo "  guaranteed to match the source (slot-aware restore is a planned follow-up; the archive" >&2
  echo "  already records shard_slot_ranges for it). Refusing before any pod starts." >&2
  exit 1
}

refuse_cluster_restore

seed_multipart_aof_from_rdb

rm -f "${placeholder}" && sync
echo "INFO: Restore complete."
