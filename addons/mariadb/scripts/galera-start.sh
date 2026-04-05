#!/bin/bash
set -eo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/mysql}"
GALERA_CONFIG="/etc/mysql/conf.d/my.cnf"

# Build wsrep_cluster_address from PEER_FQDNS (comma-separated FQDNs)
# PEER_FQDNS is injected by KubeBlocks via componentVarRef.podFQDNs
build_cluster_address() {
  local fqdns="${PEER_FQDNS:-}"
  if [ -z "$fqdns" ]; then
    echo "gcomm://"
    return
  fi
  # Convert comma-separated FQDNs to gcomm:// address
  local addr
  addr=$(echo "$fqdns" | tr ',' '\n' | awk '{printf ",%s:4567", $1}' | cut -c2-)
  echo "gcomm://${addr}"
}

# Detect if this is the bootstrap node:
# - Pod index 0 (name ends in -0)
# - Data directory is empty (fresh cluster)
should_bootstrap() {
  local pod_index="${POD_NAME##*-}"
  if [ "$pod_index" != "0" ]; then
    return 1
  fi
  # Check if data dir is empty (no mysql system tables yet)
  if [ ! -d "${DATA_DIR}/mysql" ]; then
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

  local wsrep_args=(
    "--wsrep-on=ON"
    "--wsrep-provider=/usr/lib/galera/libgalera_smm.so"
    "--wsrep-cluster-address=${cluster_address}"
    "--wsrep-cluster-name=${CLUSTER_NAME:-mariadb-galera}"
    "--wsrep-node-name=${POD_NAME}"
    "--wsrep-node-address=${POD_IP:-127.0.0.1}"
    "--wsrep-sst-method=mariabackup"
    "--wsrep-sst-auth=${MARIADB_ROOT_USER}:${MARIADB_ROOT_PASSWORD}"
  )

  if should_bootstrap; then
    echo "Bootstrapping new Galera cluster..."
    exec mariadbd "${wsrep_args[@]}" --wsrep-new-cluster \
      --mariadb-root-host="${MARIADB_ROOT_HOST:-%}" "$@"
  else
    echo "Joining Galera cluster at ${cluster_address}..."
    exec mariadbd "${wsrep_args[@]}" \
      --mariadb-root-host="${MARIADB_ROOT_HOST:-%}" "$@"
  fi
}

main "$@"
