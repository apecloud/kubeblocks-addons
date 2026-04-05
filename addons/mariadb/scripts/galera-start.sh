#!/bin/bash
set -eo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"

# Build wsrep_cluster_address from PEER_FQDNS (comma-separated FQDNs injected by KubeBlocks)
build_cluster_address() {
  local fqdns="${PEER_FQDNS:-}"
  if [ -z "$fqdns" ]; then
    echo "gcomm://"
    return
  fi
  local addr
  addr=$(echo "$fqdns" | tr ',' '\n' | awk '{printf ",%s:4567", $1}' | cut -c2-)
  echo "gcomm://${addr}"
}

# Determine whether this node should bootstrap.
#
# Bootstrap if EITHER:
#   (a) Fresh cluster: this is pod-0 and there is no initialized data directory yet.
#   (b) Restart after full cluster shutdown: grastate.dat has safe_to_bootstrap=1,
#       meaning this is the last node that shut down cleanly.
should_bootstrap() {
  local pod_index="${POD_NAME##*-}"

  # (b) grastate.dat says we are safe to bootstrap (after full cluster shutdown)
  if [ -f "${DATA_DIR}/grastate.dat" ]; then
    if grep -q "^safe_to_bootstrap: 1" "${DATA_DIR}/grastate.dat"; then
      echo "grastate.dat: safe_to_bootstrap=1, this node will bootstrap the cluster."
      return 0
    fi
    # Another node has safe_to_bootstrap=1 — join, don't bootstrap
    return 1
  fi

  # (a) Fresh cluster: no data directory, must be pod-0
  if [ "$pod_index" = "0" ] && [ ! -d "${DATA_DIR}/mysql" ]; then
    echo "Fresh cluster, pod-0 will bootstrap."
    return 0
  fi

  return 1
}

setup_data_dir() {
  mkdir -p "${DATA_DIR}"/{log,binlog,tmp}
  chown -R mysql:mysql "${DATA_DIR}" || true
}

main() {
  setup_data_dir

  local cluster_address
  cluster_address=$(build_cluster_address)

  # wsrep_sst_auth is read from WSREP_SST_AUTH env var which is set from
  # MARIADB_ROOT_USER/MARIADB_ROOT_PASSWORD injected by KubeBlocks credential vars.
  # Passing it via --wsrep-sst-auth on the command line would expose it in ps output.
  # Instead, write it to a temporary config snippet that is only root-readable.
  local sst_conf="/etc/mysql/conf.d/galera-sst-auth.cnf"
  mkdir -p "$(dirname "$sst_conf")"
  printf '[mysqld]\nwsrep_sst_auth=%s:%s\n' \
    "${MARIADB_ROOT_USER}" "${MARIADB_ROOT_PASSWORD}" > "$sst_conf"
  chmod 600 "$sst_conf"

  local wsrep_args=(
    "--wsrep-cluster-address=${cluster_address}"
    "--wsrep-cluster-name=${CLUSTER_NAME:-mariadb-galera}"
    "--wsrep-node-name=${POD_NAME}"
    "--wsrep-node-address=${POD_IP:-127.0.0.1}"
  )

  if should_bootstrap; then
    echo "Starting Galera cluster bootstrap (--wsrep-new-cluster)..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}" --wsrep-new-cluster
  else
    echo "Joining Galera cluster at ${cluster_address}..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}"
  fi
}

main "$@"
