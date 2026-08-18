#!/bin/bash
set -euo pipefail

: "${PD_POD_FQDNS:?PD_POD_FQDNS is required}"
: "${STORE_POD_FQDNS:?STORE_POD_FQDNS is required}"

append_port() {
  local list=$1
  local port=$2
  local out="" host
  IFS=',' read -ra hosts <<< "${list}"
  for host in "${hosts[@]}"; do
    [[ -n "${host}" ]] || continue
    [[ -n "${out}" ]] && out+=","
    out+="${host}:${port}"
  done
  printf '%s' "${out}"
}

first_store=${STORE_POD_FQDNS%%,*}

export HG_SERVER_BACKEND=hstore
export HG_SERVER_PD_PEERS="$(append_port "${PD_POD_FQDNS}" 8686)"
export HG_SERVER_USE_PD=true
export HG_SERVER_INIT_STORE_ENABLED=false
export STORE_REST="${first_store}:8520"

cd /hugegraph-server
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
