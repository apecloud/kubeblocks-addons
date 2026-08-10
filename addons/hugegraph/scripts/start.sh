#!/usr/bin/env bash

set -Eeuo pipefail

SERVER_HOME=${HUGEGRAPH_SERVER_HOME:-/hugegraph-server}
DATA_ROOT=${HUGEGRAPH_DATA_ROOT:-/hugegraph-data}
GRAPH_DIR="${DATA_ROOT}/graphs"
REST_CONFIG="${SERVER_HOME}/conf/rest-server.properties"
DEFAULT_GRAPH_CONFIG="${SERVER_HOME}/conf/graphs/hugegraph.properties"

log() {
  echo "INFO: $*"
}

fail() {
  echo "ERROR: $*" >&2
  exit 1
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

set_property() {
  local file=$1
  local key=$2
  local value=$3
  local escaped_key=${key//./\.}

  if grep -Eq "^[[:space:]]*${escaped_key}[[:space:]]*=" "$file"; then
    sed -i -E "s#^[[:space:]]*${escaped_key}[[:space:]]*=.*#${key}=${value}#" "$file"
  else
    printf '%s=%s\n' "$key" "$value" >>"$file"
  fi
}

validate_direct_child() {
  local path=$1
  local label=$2
  [[ "$path" == "${DATA_ROOT}/"* ]] || fail "${label} must be under ${DATA_ROOT}: ${path}"
  [[ "$(dirname "$path")" == "$DATA_ROOT" ]] || fail "${label} must be a direct child of ${DATA_ROOT}: ${path}"
  [[ "$(basename "$path")" =~ ^[A-Za-z0-9._-]+$ ]] || fail "${label} has an unsafe directory name: ${path}"
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

mkdir -p "$GRAPH_DIR" "${DATA_ROOT}/docker"

if ! compgen -G "${GRAPH_DIR}/*.properties" >/dev/null; then
  log "installing the default graph configuration into persistent storage"
  cp "$DEFAULT_GRAPH_CONFIG" "${GRAPH_DIR}/hugegraph.properties"
fi

set_property "$REST_CONFIG" restserver.url http://0.0.0.0:8080
set_property "$REST_CONFIG" graphs "$GRAPH_DIR"

shopt -s nullglob
graph_configs=("${GRAPH_DIR}"/*.properties)
(( ${#graph_configs[@]} > 0 )) || fail "no graph configuration found in ${GRAPH_DIR}"
declare -A path_owners=()

for graph_config in "${graph_configs[@]}"; do
  graph_name=$(basename "$graph_config" .properties)
  backend=$(read_property "$graph_config" backend)
  store=$(read_property "$graph_config" store)
  data_path=$(read_property "$graph_config" rocksdb.data_path)
  wal_path=$(read_property "$graph_config" rocksdb.wal_path)

  [[ "$graph_name" =~ ^[A-Za-z][A-Za-z0-9_]{0,47}$ ]] || fail "invalid graph name from config: ${graph_name}"
  [[ "$backend" == "rocksdb" ]] || fail "graph ${graph_name} uses unsupported backend ${backend:-<empty>}"
  [[ "${store,,}" == "${graph_name,,}" ]] || fail "graph config ${graph_name} must use store=${graph_name}, got ${store:-<empty>}"

  if [[ "$graph_name" == "hugegraph" ]]; then
    data_path=${data_path:-${DATA_ROOT}/rocksdb}
    wal_path=${wal_path:-${DATA_ROOT}/wal}
    set_property "$graph_config" rocksdb.data_path "$data_path"
    set_property "$graph_config" rocksdb.wal_path "$wal_path"
  else
    [[ -n "$data_path" && -n "$wal_path" ]] || fail "graph ${graph_name} must set persistent rocksdb.data_path and rocksdb.wal_path"
  fi

  validate_managed_path "$data_path" "graph ${graph_name} data path"
  validate_managed_path "$wal_path" "graph ${graph_name} WAL path"
  [[ "$data_path" != "$wal_path" ]] || fail "graph ${graph_name} data and WAL paths must differ"
  for managed_path in "$data_path" "$wal_path"; do
    [[ -z "${path_owners[$managed_path]:-}" ]] || fail "path ${managed_path} is shared by ${path_owners[$managed_path]} and ${graph_name}"
    path_owners[$managed_path]=$graph_name
  done

  set_property "$graph_config" gremlin.graph org.apache.hugegraph.auth.HugeFactoryAuthProxy
done

docker_marker="${SERVER_HOME}/docker"
if [[ -e "$docker_marker" && ! -L "$docker_marker" ]]; then
  if [[ -d "$docker_marker" && -z "$(find "$docker_marker" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
    rmdir "$docker_marker"
  else
    fail "${docker_marker} exists and is not an empty directory or symlink"
  fi
fi
ln -sfn "${DATA_ROOT}/docker" "$docker_marker"

log "starting HugeGraph with ${#graph_configs[@]} persistent graph configuration(s)"
cd "$SERVER_HOME"
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
