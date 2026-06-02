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

# Check whether any peer node has a functioning Galera Primary component.
# Used to distinguish "full cluster restart" (no peers with Primary — pod-0
# should bootstrap) from "single pod restart" (peers with Primary — must
# join, not bootstrap, to avoid split-brain).
#
# A simple TCP probe on port 3306 is insufficient: MariaDB in join mode
# opens port 3306 while stuck in non-Primary/Initialized state. If all
# pods restart simultaneously (podManagementPolicy=Parallel), pod-1/pod-2
# start in join mode with 3306 open, and a TCP-only check would make
# pod-0 also join → all three deadlocked in non-Primary.
#
# Instead, query wsrep_cluster_status on each reachable peer. Only
# "Primary" means the peer belongs to a functioning cluster.
_any_peer_alive() {
  local fqdns="${PEER_FQDNS:-}"
  [ -z "$fqdns" ] && return 1
  local peer
  for peer in $(echo "$fqdns" | tr ',' ' '); do
    echo "$peer" | grep -q "${POD_NAME}" && continue
    if timeout 3 bash -c "echo > /dev/tcp/${peer}/3306" 2>/dev/null; then
      local cluster_status
      cluster_status=$(timeout 5 mariadb \
        -u"${MARIADB_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" \
        -h "${peer}" -N -s \
        -e "SHOW STATUS LIKE 'wsrep_cluster_status';" 2>/dev/null \
        | awk '{print $2}')
      if [ "${cluster_status}" = "Primary" ]; then
        echo "Peer ${peer} is alive with wsrep_cluster_status=Primary."
        return 0
      fi
      echo "Peer ${peer} port 3306 open but wsrep_cluster_status=${cluster_status:-unreachable} (not Primary, skipping)."
    fi
  done
  return 1
}

# Wait until at least one peer has a Primary component before starting
# MariaDB in join mode. Prevents non-pod-0 nodes from forming a dead
# non-Primary group during full cluster restart:
#
# Without this wait, pod-1/pod-2 start MariaDB in join mode, connect to
# each other via Galera group communication, and form a 2-node non-Primary
# partition (seqno=-1, can't elect primary). Meanwhile pod-0 bootstraps
# independently. The two partitions are separate Galera clusters — pod-1/2
# will never discover pod-0's new primary because they're already locked
# in their own dead group communication session.
#
# With this wait, pod-1/pod-2 delay starting MariaDB until pod-0 has
# bootstrapped and is reporting wsrep_cluster_status=Primary. They then
# join pod-0's cluster cleanly.
_wait_for_primary_peer() {
  if _any_peer_alive; then
    return 0
  fi
  echo "No peer has Primary component. Waiting for bootstrap node..."
  local max_wait=120
  local elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    sleep 3
    elapsed=$((elapsed + 3))
    if _any_peer_alive; then
      echo "Found peer with Primary component after ${elapsed}s."
      return 0
    fi
  done
  echo "No Primary peer found after ${max_wait}s. Starting join anyway."
  return 0
}

# Run wsrep-recover to extract the last committed position from InnoDB,
# then mark grastate.dat safe_to_bootstrap=1 so MariaDB will accept
# --wsrep-new-cluster on the next exec.
_wsrep_recover_and_bootstrap() {
  local recover_output
  recover_output=$(mariadbd --wsrep-recover 2>&1) || true
  local recovered_seqno
  recovered_seqno=$(echo "$recover_output" | grep 'Recovered position' | sed 's/.*://' | tail -1)
  echo "wsrep-recover: seqno=${recovered_seqno:-unknown}"
  sed -i 's/^safe_to_bootstrap: 0/safe_to_bootstrap: 1/' "${DATA_DIR}/grastate.dat"
  echo "grastate.dat updated: safe_to_bootstrap=1 for crash recovery bootstrap."
}

# Determine whether this node should bootstrap.
#
# ONLY pod-0 may bootstrap — this prevents split-brain when parallel shutdown
# (podManagementPolicy=Parallel) causes multiple nodes to have safe_to_bootstrap=1.
# Galera uses synchronous replication, so all nodes have identical committed data;
# pod-0 is always a safe bootstrap candidate.
#
# Bootstrap if ALL of: this is pod-0, AND no peer is already running, AND one of:
#   (a) Fresh cluster: no initialized data directory yet.
#   (b) Restart after clean shutdown: grastate.dat has safe_to_bootstrap=1.
#   (c) Full cluster crash recovery: grastate.dat has safe_to_bootstrap=0.
#       Runs wsrep-recover to validate InnoDB consistency before bootstrap.
should_bootstrap() {
  local pod_index="${POD_NAME##*-}"

  if [ -f "${DATA_DIR}/grastate.dat" ]; then
    # Non-pod-0 never bootstraps — always join.
    if [ "$pod_index" != "0" ]; then
      if grep -q "^safe_to_bootstrap: 1" "${DATA_DIR}/grastate.dat"; then
        echo "Non-pod-0: safe_to_bootstrap=1 ignored (single-owner bootstrap). Will join."
      fi
      return 1
    fi

    # Pod-0: if any peer is already running, join instead of bootstrapping.
    # This handles single-pod restart and rolling restart correctly.
    if _any_peer_alive; then
      echo "Peers alive. Pod-0 will join existing cluster."
      return 1
    fi

    # Pod-0, no peers alive: this is a full cluster restart.
    if grep -q "^safe_to_bootstrap: 1" "${DATA_DIR}/grastate.dat"; then
      echo "grastate.dat: safe_to_bootstrap=1, pod-0 will bootstrap."
    else
      echo "No peers alive. Pod-0 crash recovery bootstrap..."
      _wsrep_recover_and_bootstrap
    fi
    return 0
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
    local pod_index="${POD_NAME##*-}"
    if [ "$pod_index" != "0" ]; then
      _wait_for_primary_peer
    fi
    echo "Joining Galera cluster at ${cluster_address}..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}"
  fi
}

main "$@"
