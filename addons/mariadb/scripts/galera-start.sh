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

  # wsrep_sst_auth must not appear on the command line (visible in ps output).
  # Write it to a file under DATA_DIR (the persistent volume, always writable)
  # and load it via --defaults-extra-file so MariaDB picks it up at startup.
  local sst_conf="${DATA_DIR}/.galera-sst-auth.cnf"
  printf '[mysqld]\nwsrep_sst_auth=%s:%s\n' \
    "${MARIADB_ROOT_USER}" "${MARIADB_ROOT_PASSWORD}" > "$sst_conf"
  chown mysql:mysql "$sst_conf"
  chmod 600 "$sst_conf"

  local wsrep_args=(
    "--defaults-extra-file=${sst_conf}"
    "--wsrep-cluster-address=${cluster_address}"
    "--wsrep-cluster-name=${CLUSTER_NAME:-mariadb-galera}"
    "--wsrep-node-name=${POD_NAME}"
    "--wsrep-node-address=${POD_IP:-127.0.0.1}"
  )

  # Background watcher: persistently write current Galera role/state to files
  # under DATA_DIR. The kbagent sidecar (kubeblocks-tools image) has no mariadb
  # client binary, so it cannot query wsrep_local_state directly. The new KB
  # main API also dropped ExecAction.container, which means probe/action scripts
  # always run inside kbagent — never inside the mariadb container. Therefore
  # the only working pattern is: data plane writes role to a shared file, and
  # the kbagent-side probe reads that file.
  #
  # Files written:
  #   ${DATA_DIR}/.galera-role    — "primary" when wsrep_local_state=4, otherwise "secondary"
  #   ${DATA_DIR}/.galera-synced  — touched once after first time state reaches 4
  #
  # The watcher must be tolerant of failures (mariadbd not yet listening,
  # transient socket errors, SST in progress). Disable set -e inside the
  # subshell so a single failed query never kills the loop. Run forever
  # so role flapping (state transitions Synced → Donor/Joining → Synced)
  # is reflected in the file in near real time.
  (
    set +e
    rm -f "${DATA_DIR}/.galera-synced" "${DATA_DIR}/.galera-role"
    SOCK=/run/mysqld/mysqld.sock
    SYNCED_ONCE=0
    while true; do
      STATE=""
      if [ -S "${SOCK}" ]; then
        STATE=$(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
          -S "${SOCK}" -N -s \
          -e "SHOW STATUS LIKE 'wsrep_local_state';" 2>/dev/null \
          | awk '{print $2}')
      fi
      if [ "${STATE}" = "4" ]; then
        printf "primary" > "${DATA_DIR}/.galera-role.tmp" \
          && chown mysql:mysql "${DATA_DIR}/.galera-role.tmp" 2>/dev/null \
          ; mv "${DATA_DIR}/.galera-role.tmp" "${DATA_DIR}/.galera-role"
        if [ "${SYNCED_ONCE}" = "0" ]; then
          touch "${DATA_DIR}/.galera-synced"
          chown mysql:mysql "${DATA_DIR}/.galera-synced" 2>/dev/null || true
          SYNCED_ONCE=1
        fi
      else
        printf "secondary" > "${DATA_DIR}/.galera-role.tmp" \
          && chown mysql:mysql "${DATA_DIR}/.galera-role.tmp" 2>/dev/null \
          ; mv "${DATA_DIR}/.galera-role.tmp" "${DATA_DIR}/.galera-role"
      fi
      sleep 3
    done
  ) &

  if should_bootstrap; then
    echo "Starting Galera cluster bootstrap (--wsrep-new-cluster)..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}" --wsrep-new-cluster
  else
    echo "Joining Galera cluster at ${cluster_address}..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}"
  fi
}

main "$@"
