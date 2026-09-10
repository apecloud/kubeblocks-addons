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

count_hosts() {
  local list=$1
  local n=0 host
  IFS=',' read -ra hosts <<< "${list}"
  for host in "${hosts[@]}"; do
    [[ -n "${host}" ]] || continue
    n=$((n + 1))
  done
  printf '%s' "${n}"
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

store_count="$(count_hosts "${STORE_POD_FQDNS}")"
[[ "${store_count}" -ge 1 ]] || {
  echo "cannot derive store count from STORE_POD_FQDNS=${STORE_POD_FQDNS}" >&2
  exit 1
}

export HG_PD_GRPC_HOST="${self}"
export HG_PD_GRPC_PORT="${HG_PD_GRPC_PORT:-8686}"
export HG_PD_REST_PORT="${HG_PD_REST_PORT:-8620}"
export HG_PD_RAFT_ADDRESS="${self}:8610"
export HG_PD_RAFT_PEERS_LIST="$(append_port "${PD_POD_FQDNS}" 8610)"
export HG_PD_INITIAL_STORE_LIST="$(append_port "${STORE_POD_FQDNS}" 8500)"
export HG_PD_DATA_PATH="${HG_PD_DATA_PATH:-/hugegraph-pd/pd_data}"
# Official pd.initial-store-count must match the expected store count
# (3 for 3 stores). Defaulting to 1 activates the cluster on the first
# Store and can leave the remaining members out of the first partition
# allocation.
export HG_PD_INITIAL_STORE_COUNT="${HG_PD_INITIAL_STORE_COUNT:-${store_count}}"

if [[ "${HG_PD_DRY_RUN:-0}" == "1" ]]; then
  printf 'HG_PD_INITIAL_STORE_COUNT=%s\n' "${HG_PD_INITIAL_STORE_COUNT}"
  printf 'HG_PD_INITIAL_STORE_LIST=%s\n' "${HG_PD_INITIAL_STORE_LIST}"
  exit 0
fi

mkdir -p "${HG_PD_DATA_PATH}"
cd /hugegraph-pd
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
