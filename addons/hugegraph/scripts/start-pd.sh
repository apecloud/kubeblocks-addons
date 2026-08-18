#!/bin/bash
set -euo pipefail

: "${PD_POD_FQDNS:?PD_POD_FQDNS is required}"
: "${STORE_POD_FQDNS:?STORE_POD_FQDNS is required}"

pod_name=${POD_NAME:-$(hostname)}

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

self=""
IFS=',' read -ra hosts <<< "${PD_POD_FQDNS}"
for host in "${hosts[@]}"; do
  short=${host%%.*}
  if [[ "${short}" == "${pod_name}" || "${host}" == "${pod_name}" ]]; then
    self=${host}
    break
  fi
done
[[ -n "${self}" ]] || {
  echo "cannot map pod ${pod_name} to PD_POD_FQDNS=${PD_POD_FQDNS}" >&2
  exit 1
}

export HG_PD_GRPC_HOST="${self}"
export HG_PD_GRPC_PORT="${HG_PD_GRPC_PORT:-8686}"
export HG_PD_REST_PORT="${HG_PD_REST_PORT:-8620}"
export HG_PD_RAFT_ADDRESS="${self}:8610"
export HG_PD_RAFT_PEERS_LIST="$(append_port "${PD_POD_FQDNS}" 8610)"
export HG_PD_INITIAL_STORE_LIST="$(append_port "${STORE_POD_FQDNS}" 8500)"
export HG_PD_DATA_PATH="${HG_PD_DATA_PATH:-/hugegraph-pd/pd_data}"
export HG_PD_INITIAL_STORE_COUNT="${HG_PD_INITIAL_STORE_COUNT:-1}"

mkdir -p "${HG_PD_DATA_PATH}"
cd /hugegraph-pd
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
