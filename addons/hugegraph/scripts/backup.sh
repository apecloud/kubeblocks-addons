#!/usr/bin/env bash

set -Eeuo pipefail

DATA_ROOT=${DATA_ROOT:-/hugegraph-data}
GRAPH_DIR="${DATA_ROOT}/graphs"
API_PORT=${API_PORT:-8080}
FORMAT_VERSION=1
ENGINE_VERSION=1.7.0
LOCK_DIR="${DATA_ROOT}/.kb-checkpoint-backup-lock"
META_DIR=""
checkpoint_dirs=()
checkpoint_cleanup_enabled=0

log() {
  echo "INFO: $*"
}

fail() {
  echo "ERROR: $*" >&2
  return 1
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

validate_direct_child() {
  local path=$1
  local label=$2
  [[ "$path" == "${DATA_ROOT}/"* ]] || fail "${label} is outside ${DATA_ROOT}: ${path}"
  [[ "$(dirname "$path")" == "$DATA_ROOT" ]] || fail "${label} is not a direct child of ${DATA_ROOT}: ${path}"
  [[ "$(basename "$path")" =~ ^[A-Za-z0-9._-]+$ ]] || fail "${label} has an unsafe name: ${path}"
}

validate_managed_path() {
  local path=$1
  local label=$2
  local name

  validate_direct_child "$path" "$label"
  name=$(basename "$path")
  case "$name" in
    graphs|docker|lost+found|snapshot_*|.kb-*)
      fail "${label} uses reserved path ${path}"
      ;;
  esac
}

cleanup() {
  local path

  if (( checkpoint_cleanup_enabled == 1 )); then
    while IFS= read -r -d '' path; do
      checkpoint_dirs+=("$path")
    done < <(find "$DATA_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'snapshot_*' -print0)
  fi
  for path in "${checkpoint_dirs[@]:-}"; do
    [[ -n "$path" ]] || continue
    if [[ "$path" == "${DATA_ROOT}/snapshot_"* && "$(dirname "$path")" == "$DATA_ROOT" ]]; then
      rm -rf -- "$path"
    fi
  done
  [[ -n "$META_DIR" ]] && rm -rf -- "$META_DIR"
  rmdir "$LOCK_DIR" 2>/dev/null || true
}

on_exit() {
  local code=$?
  if (( code != 0 )); then
    echo "checkpoint backup failed with exit code ${code}" >&2
    [[ -n "${DP_BACKUP_INFO_FILE:-}" ]] && touch "${DP_BACKUP_INFO_FILE}.exit"
  fi
  cleanup
  exit "$code"
}
trap on_exit EXIT

: "${DP_DATASAFED_BIN_PATH:?DP_DATASAFED_BIN_PATH is required}"
: "${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required}"
: "${DP_BACKUP_NAME:?DP_BACKUP_NAME is required}"
: "${DP_BACKUP_INFO_FILE:?DP_BACKUP_INFO_FILE is required}"
: "${DP_DB_HOST:?DP_DB_HOST is required}"
: "${DP_DB_USER:?DP_DB_USER is required}"
: "${DP_DB_PASSWORD:?DP_DB_PASSWORD is required}"

export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="$DP_BACKUP_BASE_PATH"

mkdir "$LOCK_DIR" 2>/dev/null || fail "another checkpoint backup is active on this PVC"
META_DIR=$(mktemp -d "${DATA_ROOT}/.kb-checkpoint-meta.XXXXXX")

shopt -s nullglob
graph_configs=("${GRAPH_DIR}"/*.properties)
(( ${#graph_configs[@]} > 0 )) || fail "no persistent graph configuration found"

preexisting=("${DATA_ROOT}"/snapshot_*)
(( ${#preexisting[@]} == 0 )) || fail "pre-existing snapshot_* directories must be resolved before backup"
checkpoint_cleanup_enabled=1

declare -a graph_names=()
declare -a config_hashes=()
declare -A path_owners=()
declare -A expected_checkpoints=()

for graph_config in "${graph_configs[@]}"; do
  graph_name=$(basename "$graph_config" .properties)
  backend=$(read_property "$graph_config" backend)
  store=$(read_property "$graph_config" store)
  data_path=$(read_property "$graph_config" rocksdb.data_path)
  wal_path=$(read_property "$graph_config" rocksdb.wal_path)
  graph_factory=$(read_property "$graph_config" gremlin.graph)

  [[ "$graph_name" =~ ^[A-Za-z][A-Za-z0-9_]{0,47}$ ]] || fail "invalid graph name from config: ${graph_name}"
  [[ "$backend" == "rocksdb" ]] || fail "graph ${graph_name} is not RocksDB"
  [[ "${store,,}" == "${graph_name,,}" ]] || fail "graph ${graph_name} has mismatched store=${store:-<empty>}"
  [[ "$graph_factory" == "org.apache.hugegraph.auth.HugeFactoryAuthProxy" ]] || fail "graph ${graph_name} is not using HugeFactoryAuthProxy"
  [[ -n "$data_path" && -n "$wal_path" ]] || fail "graph ${graph_name} must declare RocksDB data and WAL paths"
  validate_managed_path "$data_path" "graph ${graph_name} data path"
  validate_managed_path "$wal_path" "graph ${graph_name} WAL path"
  [[ "$data_path" != "$wal_path" ]] || fail "graph ${graph_name} data and WAL paths are identical"

  for owned_path in "$data_path" "$wal_path"; do
    [[ -z "${path_owners[$owned_path]:-}" ]] || fail "path ${owned_path} is shared by ${path_owners[$owned_path]} and ${graph_name}"
    path_owners[$owned_path]=$graph_name
  done

  graph_names+=("$graph_name")
  config_hashes+=("$(sha256sum "$graph_config" | awk '{print $1}')")
  expected_checkpoints["snapshot_$(basename "$data_path")"]=$graph_name
done

for graph_name in "${graph_names[@]}"; do
  log "creating checkpoint for graph ${graph_name}"
  curl --fail --silent --show-error \
    --user "${DP_DB_USER}:${DP_DB_PASSWORD}" \
    --request PUT \
    "http://${DP_DB_HOST}:${API_PORT}/graphspaces/DEFAULT/graphs/${graph_name}/snapshot_create" \
    >/dev/null
done

while IFS= read -r -d '' checkpoint; do
  checkpoint_dirs+=("$checkpoint")
done < <(find "$DATA_ROOT" -mindepth 1 -maxdepth 1 -type d -name 'snapshot_*' -print0 | sort -z)

(( ${#checkpoint_dirs[@]} == ${#graph_names[@]} )) || fail "checkpoint directory count does not match graph count"

declare -a checkpoint_names=()
for checkpoint in "${checkpoint_dirs[@]}"; do
  checkpoint_name=$(basename "$checkpoint")
  origin_name=${checkpoint_name#snapshot_}
  [[ "$checkpoint_name" == snapshot_* && -n "$origin_name" ]] || fail "invalid checkpoint directory ${checkpoint_name}"
  [[ "$checkpoint_name" =~ ^snapshot_[A-Za-z0-9._-]+$ ]] || fail "unsafe checkpoint directory ${checkpoint_name}"
  [[ "$origin_name" =~ ^[A-Za-z0-9._-]+$ ]] || fail "unsafe checkpoint destination ${origin_name}"
  [[ -n "${expected_checkpoints[$checkpoint_name]:-}" ]] || fail "checkpoint ${checkpoint_name} does not map to a graph data path"
  [[ -z "$(find "$checkpoint" -type l -print -quit)" ]] || fail "checkpoint ${checkpoint_name} contains symbolic links"
  [[ -z "$(find "$checkpoint" ! -type d ! -type f -print -quit)" ]] || fail "checkpoint ${checkpoint_name} contains a special file"
  while IFS= read -r -d '' member; do
    relative=${member#"${DATA_ROOT}/"}
    [[ "$relative" =~ ^[A-Za-z0-9._/-]+$ ]] || fail "checkpoint ${checkpoint_name} contains an unsafe path: ${relative}"
  done < <(find "$checkpoint" -mindepth 1 -print0)
  [[ -n "$(find "$checkpoint" -type f -size +0c -print -quit)" ]] || fail "checkpoint ${checkpoint_name} contains no non-empty files"
  checkpoint_names+=("$checkpoint_name")
  unset 'expected_checkpoints[$checkpoint_name]'
done

(( ${#expected_checkpoints[@]} == 0 )) || fail "one or more graph data paths have no checkpoint"

manifest="${META_DIR}/manifest.properties"
checksums="${META_DIR}/checksums.sha256"
{
  echo "format.version=${FORMAT_VERSION}"
  echo "engine=hugegraph"
  echo "engine.version=${ENGINE_VERSION}"
  echo "backup.type=full"
  echo "graph.count=${#graph_names[@]}"
  for i in "${!graph_names[@]}"; do
    echo "graph.${i}.name=${graph_names[$i]}"
    echo "graph.${i}.config=graphs/${graph_names[$i]}.properties"
    echo "graph.${i}.config.sha256=${config_hashes[$i]}"
  done
  echo "checkpoint.count=${#checkpoint_names[@]}"
  for i in "${!checkpoint_names[@]}"; do
    echo "checkpoint.${i}.source=${checkpoint_names[$i]}"
    echo "checkpoint.${i}.destination=${checkpoint_names[$i]#snapshot_}"
  done
} >"$manifest"

: >"$checksums"
for graph_config in "${graph_configs[@]}"; do
  relative="graphs/$(basename "$graph_config")"
  printf '%s  %s\n' "$(sha256sum "$graph_config" | awk '{print $1}')" "$relative" >>"$checksums"
done
for checkpoint in "${checkpoint_dirs[@]}"; do
  while IFS= read -r file; do
    relative=${file#"${DATA_ROOT}/"}
    printf '%s  %s\n' "$(sha256sum "$file" | awk '{print $1}')" "$relative" >>"$checksums"
  done < <(find "$checkpoint" -type f -print | LC_ALL=C sort)
done

cp "$manifest" "${META_DIR}/manifest.upload"
cp "$checksums" "${META_DIR}/checksums.upload"
datasafed push "${META_DIR}/manifest.upload" manifest.properties
datasafed push "${META_DIR}/checksums.upload" checksums.sha256

log "uploading checkpoint payload"
graph_entries=()
for graph_config in "${graph_configs[@]}"; do
  graph_entries+=("graphs/$(basename "$graph_config")")
done
tar -C "$DATA_ROOT" -czf - "${graph_entries[@]}" "${checkpoint_names[@]}" \
  -C "$META_DIR" manifest.properties checksums.sha256 \
  | datasafed push - payload.tar.gz

total_size=$(datasafed stat / | awk '/TotalSize/ {print $2; exit}')
[[ -n "$total_size" ]] || fail "datasafed did not report backup size"
printf '{"totalSize":"%s"}\n' "$total_size" >"$DP_BACKUP_INFO_FILE"
log "checkpoint backup completed for ${#graph_names[@]} graph(s)"
