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

export HG_STORE_PD_ADDRESS="$(append_port "${PD_POD_FQDNS}" 8686)"
first_pd=${PD_POD_FQDNS%%,*}
attempts=${HG_STORE_HEALTH_ATTEMPTS:-60}
sleep_secs=${HG_STORE_HEALTH_SLEEP:-2}
pd_healthy=0
for _ in $(seq 1 "${attempts}"); do
  if curl -fsS "http://${first_pd}:8620/v1/health" >/dev/null; then
    pd_healthy=1
    break
  fi
  sleep "${sleep_secs}"
done
[[ "${pd_healthy}" -eq 1 ]] || {
  echo "PD is not healthy at http://${first_pd}:8620/v1/health after ${attempts} attempt(s)" >&2
  exit 1
}
export HG_STORE_GRPC_HOST="${self}"
export HG_STORE_GRPC_PORT="${HG_STORE_GRPC_PORT:-8500}"
export HG_STORE_REST_PORT="${HG_STORE_REST_PORT:-8520}"
export HG_STORE_RAFT_ADDRESS="${self}:8510"
export HG_STORE_DATA_PATH="${HG_STORE_DATA_PATH:-/hugegraph-store/storage}"

mkdir -p "${HG_STORE_DATA_PATH}"
cd /hugegraph-store
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
