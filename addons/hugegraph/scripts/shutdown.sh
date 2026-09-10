#!/usr/bin/env bash

set -Eeuo pipefail

SERVER_HOME=${HUGEGRAPH_SERVER_HOME:-/hugegraph-server}
DATA_ROOT=${HUGEGRAPH_DATA_ROOT:-/hugegraph-data}
AUDIT_LOG="${DATA_ROOT}/.kb-prestop.log"

log() {
  local message
  message="$(date -u +%Y-%m-%dT%H:%M:%SZ) INFO: $*"
  printf '%s\n' "$message"
  printf '%s\n' "$message" >>"$AUDIT_LOG"
}

cd "$SERVER_HOME"
pid=$(cat ./bin/pid 2>/dev/null || true)

if [[ "$pid" =~ ^[0-9]+$ ]] && kill -0 "$pid" 2>/dev/null; then
  log "graceful shutdown started for HugeGraphServer pid ${pid}"
  ./bin/stop-hugegraph.sh
else
  log "HugeGraphServer is already stopped; skipping shutdown command"
fi

sync
log "graceful shutdown completed"
