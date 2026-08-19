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
IFS=',' read -ra hosts <<< "${STORE_POD_FQDNS}"
for host in "${hosts[@]}"; do
  short=${host%%.*}
  if [[ "${short}" == "${pod_name}" || "${host}" == "${pod_name}" ]]; then
    self=${host}
    break
  fi
done
[[ -n "${self}" ]] || {
  echo "cannot map pod ${pod_name} to STORE_POD_FQDNS=${STORE_POD_FQDNS}" >&2
  exit 1
}

pds=()
IFS=',' read -ra hosts <<< "${PD_POD_FQDNS}"
for host in "${hosts[@]}"; do
  [[ -n "${host}" ]] || continue
  pds+=("${host}")
done
[[ "${#pds[@]}" -ge 1 ]] || {
  echo "cannot derive PD list from PD_POD_FQDNS=${PD_POD_FQDNS}" >&2
  exit 1
}

export HG_STORE_PD_ADDRESS="$(append_port "${PD_POD_FQDNS}" 8686)"
attempts=${HG_STORE_HEALTH_ATTEMPTS:-60}
sleep_secs=${HG_STORE_HEALTH_SLEEP:-2}
# Official 3-PD compose waits for every PD, not only the first.
# One healthy PD is not a Raft majority.
unhealthy=""
for _ in $(seq 1 "${attempts}"); do
  unhealthy=""
  for pd in "${pds[@]}"; do
    if ! curl -fsS "http://${pd}:8620/v1/health" >/dev/null; then
      unhealthy=${pd}
      break
    fi
  done
  [[ -z "${unhealthy}" ]] && break
  sleep "${sleep_secs}"
done
[[ -z "${unhealthy}" ]] || {
  echo "PD is not healthy at http://${unhealthy}:8620/v1/health after ${attempts} attempt(s)" >&2
  exit 1
}
export HG_STORE_GRPC_HOST="${self}"
export HG_STORE_GRPC_PORT="${HG_STORE_GRPC_PORT:-8500}"
export HG_STORE_REST_PORT="${HG_STORE_REST_PORT:-8520}"
export HG_STORE_RAFT_ADDRESS="${self}:8510"
export HG_STORE_DATA_PATH="${HG_STORE_DATA_PATH:-/hugegraph-store/storage}"

if [[ "${HG_STORE_DRY_RUN:-0}" == "1" ]]; then
  printf 'pds_healthy=%s\n' "${#pds[@]}"
  exit 0
fi

mkdir -p "${HG_STORE_DATA_PATH}"
cd /hugegraph-store
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
