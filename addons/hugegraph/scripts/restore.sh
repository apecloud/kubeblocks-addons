#!/usr/bin/env bash

set -Eeuo pipefail

DATA_ROOT=${DATA_ROOT:-/hugegraph-data}
FORMAT_VERSION=1
ENGINE_VERSION=1.7.0
WORK_DIR=""
STAGING_DIR="${DATA_ROOT}/.kb-restore-staging"
IN_PROGRESS_MARKER="${DATA_ROOT}/.kb-restore-in-progress"
COMPLETE_MARKER="${DATA_ROOT}/.kb-restored-backup"
INIT_MARKER="${DATA_ROOT}/docker/init_complete"

log() {
  echo "INFO: $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

manifest_get() {
  local key=$1
  awk -F= -v key="$key" '$1 == key {print substr($0, index($0, "=") + 1); exit}' "${WORK_DIR}/manifest.properties"
}

read_property() {
  local file=$1
  local key=$2
  awk -F= -v key="$key" '
    $0 !~ /^[[:space:]]*#/ {
      lhs=$1
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", lhs)
      if (lhs == key) {
        value=substr($0, index($0, "=") + 1)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", value)
        print value
        exit
      }
    }
  ' "$file"
}

validate_count() {
  local value=$1
  local label=$2
  [[ "$value" =~ ^[1-9][0-9]*$ ]] || fail "${label} must be a positive integer, got ${value:-<empty>}"
}

validate_managed_path() {
  local path=$1
  local label=$2
  local name

  [[ "$path" == "${DATA_ROOT}/"* ]] || fail "${label} is outside ${DATA_ROOT}: ${path}"
  [[ "$(dirname "$path")" == "$DATA_ROOT" ]] || fail "${label} is not a direct child of ${DATA_ROOT}: ${path}"
  name=$(basename "$path")
  [[ "$name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "${label} has an unsafe name: ${path}"
  case "$name" in
    graphs|docker|lost+found|snapshot_*|.kb-*)
      fail "${label} uses reserved path ${path}"
      ;;
  esac
}

validate_member() {
  local member=$1
  local root
  [[ -n "$member" ]] || fail "payload contains an empty member name"
  [[ "$member" != /* ]] || fail "payload contains an absolute path: ${member}"
  [[ "$member" != ".." && "$member" != ../* && "$member" != */../* && "$member" != */.. ]] || fail "payload contains path traversal: ${member}"
  [[ "$member" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "payload contains an unsafe member name: ${member}"
  case "$member" in
    graphs|graphs/|manifest.properties|checksums.sha256)
      ;;
    graphs/*.properties)
      [[ -n "${graph_config_members[$member]:-}" ]] || fail "payload contains an unlisted graph config: ${member}"
      ;;
    *)
      root=${member%%/*}
      [[ -n "${checkpoint_source_members[$root]:-}" ]] || fail "payload contains an unlisted checkpoint member: ${member}"
      ;;
  esac
}

cleanup() {
  [[ -n "$WORK_DIR" ]] && rm -rf -- "$WORK_DIR"
  rm -rf -- "$STAGING_DIR"
}
trap cleanup EXIT

: "${DP_DATASAFED_BIN_PATH:?DP_DATASAFED_BIN_PATH is required}"
: "${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required}"
: "${DP_BACKUP_NAME:?DP_BACKUP_NAME is required}"

export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

WORK_DIR=$(mktemp -d /tmp/hugegraph-restore.XXXXXX)
datasafed pull manifest.properties "${WORK_DIR}/manifest.properties"
datasafed pull checksums.sha256 "${WORK_DIR}/checksums.sha256"
datasafed pull payload.tar.gz "${WORK_DIR}/payload.tar.gz"

[[ "$(manifest_get format.version)" == "$FORMAT_VERSION" ]] || fail "unsupported checkpoint format"
[[ "$(manifest_get engine)" == "hugegraph" ]] || fail "artifact is not a HugeGraph backup"
[[ "$(manifest_get engine.version)" == "$ENGINE_VERSION" ]] || fail "HugeGraph version mismatch"
[[ "$(manifest_get backup.type)" == "full" ]] || fail "only full checkpoint backup is supported"

graph_count=$(manifest_get graph.count)
checkpoint_count=$(manifest_get checkpoint.count)
validate_count "$graph_count" graph.count
validate_count "$checkpoint_count" checkpoint.count
(( checkpoint_count == graph_count )) || fail "checkpoint count does not match graph count"

declare -a checkpoint_sources=()
declare -a checkpoint_destinations=()
declare -A destinations=()
declare -A checkpoint_source_members=()
declare -A graph_names=()
declare -A graph_config_members=()
declare -A archive_members=()
declare -A checksum_members=()

for ((i = 0; i < checkpoint_count; i++)); do
  source_name=$(manifest_get "checkpoint.${i}.source")
  destination=$(manifest_get "checkpoint.${i}.destination")
  [[ "$source_name" =~ ^snapshot_[A-Za-z0-9._-]+$ ]] || fail "unsafe checkpoint source ${source_name:-<empty>}"
  [[ "$destination" =~ ^[A-Za-z0-9._-]+$ ]] || fail "unsafe checkpoint destination ${destination:-<empty>}"
  [[ "$destination" == "${source_name#snapshot_}" ]] || fail "checkpoint destination does not match source ${source_name}"
  [[ -z "${destinations[$destination]:-}" ]] || fail "duplicate checkpoint destination ${destination}"
  destinations[$destination]=1
  checkpoint_source_members[$source_name]=1
  checkpoint_sources+=("$source_name")
  checkpoint_destinations+=("$destination")
done

for ((i = 0; i < graph_count; i++)); do
  graph_name=$(manifest_get "graph.${i}.name")
  graph_config=$(manifest_get "graph.${i}.config")
  expected_hash=$(manifest_get "graph.${i}.config.sha256")
  [[ "$graph_name" =~ ^[A-Za-z][A-Za-z0-9_]{0,47}$ ]] || fail "unsafe graph name ${graph_name:-<empty>}"
  [[ -z "${graph_names[$graph_name]:-}" ]] || fail "duplicate graph name ${graph_name}"
  graph_names[$graph_name]=1
  [[ "$graph_config" == "graphs/${graph_name}.properties" ]] || fail "graph config path mismatch for ${graph_name}"
  graph_config_members[$graph_config]=1
  [[ "$expected_hash" =~ ^[a-f0-9]{64}$ ]] || fail "invalid graph config hash for ${graph_name}"
done

log "validating checkpoint payload members"
tar -tzf "${WORK_DIR}/payload.tar.gz" >"${WORK_DIR}/payload.list"
tar -tvzf "${WORK_DIR}/payload.tar.gz" >"${WORK_DIR}/payload.verbose"
while IFS= read -r line; do
  type=${line:0:1}
  [[ "$type" == "-" || "$type" == "d" ]] || fail "payload contains a non-regular member"
done <"${WORK_DIR}/payload.verbose"
while IFS= read -r member; do
  validate_member "$member"
  [[ -z "${archive_members[$member]:-}" ]] || fail "payload contains a duplicate member: ${member}"
  archive_members[$member]=1
done <"${WORK_DIR}/payload.list"
while IFS= read -r checksum_line; do
  [[ "$checksum_line" =~ ^([a-f0-9]{64})[[:space:]][[:space:]]([A-Za-z0-9._/-]+)$ ]] || fail "checksum list contains an invalid entry"
  relative=${BASH_REMATCH[2]}
  validate_member "$relative"
  if [[ "$relative" == "manifest.properties" || "$relative" == "checksums.sha256" ||
        "$relative" == "graphs" || "$relative" == "graphs/" ||
        "$relative" =~ ^snapshot_[A-Za-z0-9._-]+/?$ ]]; then
    fail "checksum list references a non-payload file: ${relative}"
  fi
  [[ -n "${archive_members[$relative]:-}" ]] || fail "checksum list references a missing archive member: ${relative}"
  [[ -z "${checksum_members[$relative]:-}" ]] || fail "checksum list contains a duplicate member: ${relative}"
  checksum_members[$relative]=1
done <"${WORK_DIR}/checksums.sha256"

rm -rf -- "$STAGING_DIR"
mkdir -p "$STAGING_DIR"
tar -xzf "${WORK_DIR}/payload.tar.gz" -C "$STAGING_DIR" --no-same-owner --no-same-permissions

cmp -s "${WORK_DIR}/manifest.properties" "${STAGING_DIR}/manifest.properties" || fail "inner and outer manifests differ"
cmp -s "${WORK_DIR}/checksums.sha256" "${STAGING_DIR}/checksums.sha256" || fail "inner and outer checksum lists differ"

while IFS= read -r -d '' payload_file; do
  relative=${payload_file#"${STAGING_DIR}/"}
  case "$relative" in
    manifest.properties|checksums.sha256)
      continue
      ;;
  esac
  [[ -n "${checksum_members[$relative]:-}" ]] || fail "payload file is not checksummed: ${relative}"
done < <(find "$STAGING_DIR" -type f -print0)

(
  cd "$STAGING_DIR"
  sha256sum -c checksums.sha256
)

declare -A graph_data_destinations=()
declare -A managed_paths=()
declare -a wal_destinations=()

for ((i = 0; i < graph_count; i++)); do
  graph_name=$(manifest_get "graph.${i}.name")
  graph_config=$(manifest_get "graph.${i}.config")
  expected_hash=$(manifest_get "graph.${i}.config.sha256")
  [[ "$(sha256sum "${STAGING_DIR}/${graph_config}" | awk '{print $1}')" == "$expected_hash" ]] || fail "graph config hash mismatch for ${graph_name}"

  backend=$(read_property "${STAGING_DIR}/${graph_config}" backend)
  store=$(read_property "${STAGING_DIR}/${graph_config}" store)
  graph_factory=$(read_property "${STAGING_DIR}/${graph_config}" gremlin.graph)
  data_path=$(read_property "${STAGING_DIR}/${graph_config}" rocksdb.data_path)
  wal_path=$(read_property "${STAGING_DIR}/${graph_config}" rocksdb.wal_path)
  [[ "$backend" == "rocksdb" ]] || fail "graph ${graph_name} is not RocksDB"
  [[ "${store,,}" == "${graph_name,,}" ]] || fail "graph ${graph_name} has mismatched store=${store:-<empty>}"
  [[ "$graph_factory" == "org.apache.hugegraph.auth.HugeFactoryAuthProxy" ]] || fail "graph ${graph_name} is not using HugeFactoryAuthProxy"
  [[ -n "$data_path" && -n "$wal_path" ]] || fail "graph ${graph_name} must declare RocksDB data and WAL paths"
  validate_managed_path "$data_path" "graph ${graph_name} data path"
  validate_managed_path "$wal_path" "graph ${graph_name} WAL path"
  [[ "$data_path" != "$wal_path" ]] || fail "graph ${graph_name} data and WAL paths are identical"
  for managed_path in "$data_path" "$wal_path"; do
    [[ -z "${managed_paths[$managed_path]:-}" ]] || fail "path ${managed_path} is shared by ${managed_paths[$managed_path]} and ${graph_name}"
    managed_paths[$managed_path]=$graph_name
  done
  data_destination=$(basename "$data_path")
  [[ -n "${destinations[$data_destination]:-}" ]] || fail "graph ${graph_name} data path has no checkpoint"
  graph_data_destinations[$data_destination]=1
  wal_destinations+=("$(basename "$wal_path")")
done

(( ${#graph_data_destinations[@]} == ${#destinations[@]} )) || fail "manifest contains a checkpoint not owned by a graph"

[[ -z "$(find "$STAGING_DIR" ! -type d ! -type f -print -quit)" ]] || fail "payload extracted a special file"

for source_name in "${checkpoint_sources[@]}"; do
  [[ -d "${STAGING_DIR}/${source_name}" ]] || fail "checkpoint directory ${source_name} is missing"
  [[ -n "$(find "${STAGING_DIR}/${source_name}" -type f -size +0c -print -quit)" ]] || fail "checkpoint ${source_name} is empty"
done

validate_restored_layout() {
  local i graph_name graph_config expected_hash destination checksum relative
  local source_root remainder actual

  [[ -d "${DATA_ROOT}/graphs" ]] || fail "restore marker exists but graph configs are missing"
  [[ -f "$INIT_MARKER" ]] || fail "restore marker exists but HugeGraph init marker is missing"
  for ((i = 0; i < graph_count; i++)); do
    graph_name=$(manifest_get "graph.${i}.name")
    graph_config=$(manifest_get "graph.${i}.config")
    expected_hash=$(manifest_get "graph.${i}.config.sha256")
    [[ -f "${DATA_ROOT}/${graph_config}" ]] || fail "restored graph config ${graph_config} is missing"
    [[ "$(sha256sum "${DATA_ROOT}/${graph_config}" | awk '{print $1}')" == "$expected_hash" ]] || fail "restored graph config hash mismatch for ${graph_name}"
  done
  for destination in "${checkpoint_destinations[@]}"; do
    [[ -d "${DATA_ROOT}/${destination}" ]] || fail "restored checkpoint destination ${destination} is missing"
    [[ -n "$(find "${DATA_ROOT}/${destination}" -type f -size +0c -print -quit)" ]] || fail "restored checkpoint destination ${destination} is empty"
  done
  while read -r checksum relative; do
    [[ "$checksum" =~ ^[a-f0-9]{64}$ && -n "$relative" ]] || fail "invalid checksum entry in completed restore"
    if [[ "$relative" == snapshot_*/* ]]; then
      source_root=${relative%%/*}
      remainder=${relative#*/}
      [[ -n "${checkpoint_source_members[$source_root]:-}" ]] || fail "checksum references an unknown checkpoint ${source_root}"
      actual="${DATA_ROOT}/${source_root#snapshot_}/${remainder}"
    else
      actual="${DATA_ROOT}/${relative}"
    fi
    [[ -f "$actual" ]] || fail "restored file ${actual} is missing"
    [[ "$(sha256sum "$actual" | awk '{print $1}')" == "$checksum" ]] || fail "restored file checksum mismatch: ${actual}"
  done <"${WORK_DIR}/checksums.sha256"
}

if [[ -f "$COMPLETE_MARKER" ]] && [[ "$(<"$COMPLETE_MARKER")" == "$DP_BACKUP_NAME" ]]; then
  validate_restored_layout
  if [[ -f "$IN_PROGRESS_MARKER" ]]; then
    [[ "$(<"$IN_PROGRESS_MARKER")" == "$DP_BACKUP_NAME" ]] || fail "completed restore has a conflicting in-progress marker"
    rm -f -- "$IN_PROGRESS_MARKER"
  fi
  log "backup ${DP_BACKUP_NAME} is already restored"
  exit 0
fi

if [[ -f "$IN_PROGRESS_MARKER" ]]; then
  [[ "$(<"$IN_PROGRESS_MARKER")" == "$DP_BACKUP_NAME" ]] || fail "PVC contains an unfinished restore from another backup"
else
  [[ ! -e "$COMPLETE_MARKER" ]] || fail "PVC was restored from another backup"
  while IFS= read -r -d '' existing; do
    case "$(basename "$existing")" in
      lost+found|.kb-restore-staging)
        ;;
      *)
        fail "target PVC is not empty: ${existing}"
        ;;
    esac
  done < <(find "$DATA_ROOT" -mindepth 1 -maxdepth 1 -print0)
fi

printf '%s\n' "$DP_BACKUP_NAME" >"$IN_PROGRESS_MARKER"

rm -rf -- "${DATA_ROOT}/graphs"
for destination in "${checkpoint_destinations[@]}"; do
  rm -rf -- "${DATA_ROOT:?}/${destination:?}"
done
for destination in "${wal_destinations[@]}"; do
  rm -rf -- "${DATA_ROOT:?}/${destination:?}"
done
rm -rf -- "${DATA_ROOT}/docker"

for i in "${!checkpoint_sources[@]}"; do
  mv "${STAGING_DIR}/${checkpoint_sources[$i]}" "${DATA_ROOT}/${checkpoint_destinations[$i]}"
done
mv "${STAGING_DIR}/graphs" "${DATA_ROOT}/graphs"
mkdir -p "$(dirname "$INIT_MARKER")"
touch "$INIT_MARKER"

sync

printf '%s\n' "$DP_BACKUP_NAME" >"${COMPLETE_MARKER}.tmp"
mv "${COMPLETE_MARKER}.tmp" "$COMPLETE_MARKER"
sync
rm -f -- "$IN_PROGRESS_MARKER"
sync
log "restored ${graph_count} graph(s) from checkpoint backup ${DP_BACKUP_NAME}"
