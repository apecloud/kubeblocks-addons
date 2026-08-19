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

stores=()
IFS=',' read -ra hosts <<< "${STORE_POD_FQDNS}"
for host in "${hosts[@]}"; do
  [[ -n "${host}" ]] || continue
  stores+=("${host}")
done
[[ "${#stores[@]}" -ge 1 ]] || {
  echo "cannot derive Store list from STORE_POD_FQDNS=${STORE_POD_FQDNS}" >&2
  exit 1
}
first_store=${stores[0]}

export HG_SERVER_BACKEND=hstore
export HG_SERVER_PD_PEERS="$(append_port "${PD_POD_FQDNS}" 8686)"
export HG_SERVER_USE_PD=true
export HG_SERVER_INIT_STORE_ENABLED=false
export STORE_REST="${first_store}:8520"

attempts=${HG_SERVER_HEALTH_ATTEMPTS:-60}
sleep_secs=${HG_SERVER_HEALTH_SLEEP:-2}
# Official 3-store compose waits for every Store, not only the first.
# With pd.initial-store-count = store count, one healthy Store is not
# enough for Cluster_OK.
unhealthy=""
for _ in $(seq 1 "${attempts}"); do
  unhealthy=""
  for store in "${stores[@]}"; do
    if ! curl -fsS "http://${store}:8520/v1/health" >/dev/null; then
      unhealthy=${store}
      break
    fi
  done
  [[ -z "${unhealthy}" ]] && break
  sleep "${sleep_secs}"
done
[[ -z "${unhealthy}" ]] || {
  echo "Store is not healthy at http://${unhealthy}:8520/v1/health after ${attempts} attempt(s)" >&2
  exit 1
}

if [[ "${HG_SERVER_DRY_RUN:-0}" == "1" ]]; then
  printf 'stores_healthy=%s\n' "${#stores[@]}"
  exit 0
fi

cd /hugegraph-server
exec /usr/bin/dumb-init -- ./docker-entrypoint.sh
