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
  local quiet="${1:-}"
  local fqdns="${PEER_FQDNS:-}"
  [ -z "$fqdns" ] && return 1
  local peer
  for peer in $(echo "$fqdns" | tr ',' ' '); do
    # Boundary self-match: "pod-1" must not match "pod-10". Compare the FQDN
    # host segment (up to the first dot) exactly against POD_NAME.
    case "${peer}" in
      "${POD_NAME}."*|"${POD_NAME}") continue ;;
    esac
    if timeout 3 bash -c "echo > /dev/tcp/${peer}/3306" 2>/dev/null; then
      # Port 3306 is open — something is listening. Query wsrep_cluster_status
      # to classify. A refused/dead peer never reaches here (TCP connect
      # fails), so an open port means the peer is up; the only question is
      # whether it is a functioning Primary we must join, or a co-restarting
      # non-Primary node we may ignore.
      #
      # Sentinel discipline (fail closed against split-brain): an EMPTY result
      # is NOT the same as a clean "not Primary" answer. Empty means the query
      # failed (auth error, SST with SQL not yet accepting, load timeout) —
      # the peer could be a live Primary we simply cannot read. Treating that
      # as "no peer" would let this node bootstrap a SECOND Primary. So we
      # retry briefly, and if the status is still unknown while the port stays
      # open, we conservatively treat the peer as alive (block bootstrap).
      local cluster_status="" attempt
      for attempt in 1 2 3; do
        cluster_status=$(timeout 5 mariadb \
          -u"${MARIADB_ROOT_USER}" -p"${MARIADB_ROOT_PASSWORD}" \
          -h "${peer}" -P3306 --ssl=0 -N -s \
          -e "SHOW STATUS LIKE 'wsrep_cluster_status';" 2>/dev/null \
          | awk '{print $2}')
        [ -n "${cluster_status}" ] && break
        sleep 1
      done
      if [ "${cluster_status}" = "Primary" ]; then
        echo "Peer ${peer} is alive with wsrep_cluster_status=Primary."
        return 0
      fi
      if [ -z "${cluster_status}" ]; then
        # Port open but status unreadable after retries → a possibly-live
        # Primary. Do NOT enable bootstrap; join/wait instead (fail closed).
        [ -z "${quiet}" ] && echo "Peer ${peer} port 3306 open but wsrep_cluster_status unreadable after retries; treating as possibly-alive to avoid split-brain bootstrap."
        return 0
      fi
      # Non-empty, non-Primary (e.g. non-Primary / Disconnected): a definitive
      # answer that the peer is not in a functioning cluster — safe to skip.
      [ -z "${quiet}" ] && echo "Peer ${peer} port 3306 open but wsrep_cluster_status=${cluster_status} (not Primary, skipping)."
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
  local max_wait="${GALERA_PRIMARY_PEER_WAIT_SECONDS:-120}"
  local elapsed=0
  while [ $elapsed -lt $max_wait ]; do
    sleep 3
    elapsed=$((elapsed + 3))
    if _any_peer_alive quiet; then
      echo "Found peer with Primary component after ${elapsed}s."
      return 0
    fi
  done
  echo "No Primary peer found after ${max_wait}s. Deferring join to avoid forming a separate non-Primary Galera partition."
  return 1
}

# Run wsrep-recover to extract the last committed position from InnoDB.
# This is local evidence only. It is not enough to decide the cluster-wide
# latest node after a full crash, because this pod cannot read peer PVCs.
_wsrep_recover_seqno() {
  local recover_output
  recover_output=$(mariadbd --wsrep-recover 2>&1) || true
  local recovered_seqno
  # `|| true`: a no-match grep returns 1 and, under set -eo pipefail, would
  # abort the script if this function is ever called outside an if/&&/||
  # context. The crash-recovery path is exactly where "Recovered position" may
  # be absent (empty/corrupt datadir), so keep it robust regardless of caller.
  recovered_seqno=$(echo "$recover_output" | grep 'Recovered position' | sed 's/.*://' | tail -1 || true)
  echo "wsrep-recover: seqno=${recovered_seqno:-unknown}"
}

_grastate_seqno() {
  awk -F: '/^seqno:/ { gsub(/^[ \t]+|[ \t]+$/, "", $2); print $2; exit }' "${DATA_DIR}/grastate.dat"
}

_mariadbd_pids() {
  pidof mariadbd 2>/dev/null || pgrep -x mariadbd 2>/dev/null || true
}

# Watcher start-up initialization: clear stale role/liveness markers left on the
# PV by a previous container generation, including any .galera-shutting-down the
# prior graceful shutdown dropped. This is a live container again, so a stale
# .galera-shutting-down would otherwise disable self-heal for the whole life of
# the new process, and a stale .galera-role/.galera-synced would let the probe
# publish a role before the watcher has re-observed Galera state. Extracted as a
# helper (not inline in the watcher subshell) so the reset is directly callable
# and unit-testable, and so any future start-up call site stays covered.
_clear_stale_markers_on_start() {
  rm -f "${DATA_DIR}/.galera-synced" \
        "${DATA_DIR}/.galera-role" \
        "${DATA_DIR}/.galera-shutting-down"
}

_restart_mariadbd_for_self_heal() {
  local reason="$1"
  # Graceful-shutdown guard: the preStop hook drops .galera-shutting-down
  # before it sets wsrep_on=OFF (which makes the node non-Primary) and runs a
  # clean shutdown that can take tens of seconds toward the 120s grace. Without
  # this guard the watcher would count that as a stuck non-Primary and SIGKILL
  # mariadbd mid-shutdown, aborting the safe_to_bootstrap write the preStop
  # exists to produce. Never self-heal-kill while shutting down.
  if [ -f "${DATA_DIR}/.galera-shutting-down" ]; then
    echo "SELF-HEALING skipped (${reason}): graceful shutdown in progress."
    return 0
  fi
  local pids
  pids=$(_mariadbd_pids)
  if [ -z "${pids}" ]; then
    echo "SELF-HEALING: ${reason}. No mariadbd process found."
    return 0
  fi

  echo "SELF-HEALING: ${reason}. Sending SIGTERM to mariadbd pid(s): ${pids}."
  kill -TERM ${pids} 2>/dev/null || echo "SELF-HEALING: SIGTERM failed for mariadbd pid(s): ${pids}."
  sleep 5

  pids=$(_mariadbd_pids)
  if [ -n "${pids}" ]; then
    echo "SELF-HEALING: mariadbd still running after SIGTERM. Sending SIGKILL to pid(s): ${pids}."
    kill -KILL ${pids} 2>/dev/null || echo "SELF-HEALING: SIGKILL failed for mariadbd pid(s): ${pids}."
  fi
}

# Determine whether this node should bootstrap.
#
# ONLY an already safe bootstrap state may bootstrap automatically. Galera may
# mark any pod safe after a clean full shutdown, not necessarily pod-0. Full
# crash recovery with safe_to_bootstrap=0 is intentionally fail-closed: this pod
# only knows its own recovered seqno and cannot prove that it is the latest node.
#
# Bootstrap if ALL of: no peer is already running, AND one of:
#   (a) Fresh cluster: no initialized data directory yet.
#   (b) Restart after clean shutdown: local grastate.dat has safe_to_bootstrap=1.
# Refuse automatic bootstrap for:
#   (c) Full cluster crash recovery: pod-0 grastate.dat has safe_to_bootstrap=0.
#       Runs wsrep-recover for local evidence, then defers instead of guessing
#       pod-0 is the latest node.
should_bootstrap() {
  local pod_index="${POD_NAME##*-}"

  if [ -f "${DATA_DIR}/grastate.dat" ]; then
    # If any peer is already running, join instead of bootstrapping.
    # This handles single-pod restart and rolling restart correctly.
    if _any_peer_alive; then
      echo "Peers alive. ${POD_NAME} will join existing cluster."
      return 1
    fi

    # No peers alive: this is a full cluster restart. seqno=-1 has TWO
    # indistinguishable-by-seqno causes that must NOT be handled the same:
    #   (1) Fresh Galera PVC: grastate.dat has seqno=-1 AND
    #       safe_to_bootstrap=1 (Galera writes stb=1 on first datadir init).
    #   (2) Hard crash (OOM-kill / node power loss / SIGKILL): a *running*
    #       node's grastate.dat also carries seqno=-1, but with
    #       safe_to_bootstrap=0 — the clean-shutdown election never ran.
    #       This is exactly the full-cluster crash the header contract (c)
    #       forbids auto-bootstrapping: pod-0 doing so would start a
    #       possibly-stale Primary and SST away committed data on 1/2.
    # So the seqno=-1 fast-path must ALSO require safe_to_bootstrap=1. A
    # seqno=-1 + stb=0 pod falls through to the fail-closed crash-recovery
    # branch below and defers instead of guessing it is the latest node.
    local grastate_seqno
    grastate_seqno=$(_grastate_seqno)
    if [ "${grastate_seqno}" = "-1" ] \
      && grep -qE "^safe_to_bootstrap:[[:space:]]+1[[:space:]]*$" "${DATA_DIR}/grastate.dat"; then
      if [ "$pod_index" = "0" ]; then
        echo "Fresh grastate.dat seqno=-1 safe_to_bootstrap=1, pod-0 will bootstrap."
        return 0
      fi
      echo "Fresh grastate.dat seqno=-1 safe_to_bootstrap=1, ${POD_NAME} will wait for pod-0 bootstrap."
      return 1
    fi

    if grep -qE "^safe_to_bootstrap:[[:space:]]+1[[:space:]]*$" "${DATA_DIR}/grastate.dat"; then
      echo "grastate.dat: safe_to_bootstrap=1, ${POD_NAME} will bootstrap."
    else
      if [ "$pod_index" = "0" ]; then
        echo "No peers alive and local grastate.dat is not safe_to_bootstrap."
        _wsrep_recover_seqno
        GALERA_BOOTSTRAP_DEFER_REASON="latest seqno unknown; refuse pod-0-only crash recovery bootstrap"
        export GALERA_BOOTSTRAP_DEFER_REASON
        echo "Refusing automatic Galera crash recovery bootstrap: latest node cannot be proven from this pod. Manual latest-seqno election is required."
      fi
      return 1
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

  # Do NOT persist wsrep_sst_auth. It is only consumed by the mariabackup/
  # xtrabackup/mysqldump SST methods; this addon uses `wsrep_sst_method = rsync`
  # (config/mariadb-galera.tpl), which does not authenticate via wsrep_sst_auth,
  # so the credential was unused. Worse, it was written to DATA_DIR — a
  # `needSnapshot: true` volume — so the plaintext root password rode into every
  # volume snapshot / backup. Remove any stale file left by a previous chart
  # version; do not recreate it.
  rm -f "${DATA_DIR}/.galera-sst-auth.cnf" 2>/dev/null || true

  local wsrep_args=(
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
  #
  # Self-healing: if wsrep_cluster_status stays non-Primary/Disconnected for
  # 90s after the socket is available, the node is stuck in a dead partition.
  # If mariadbd is running for 90s without creating the local socket, it is
  # stuck before SQL accept readiness, commonly during a failed SST/join.
  # In both cases, kill mariadbd so the container restarts and re-evaluates
  # whether to join the current Primary component (e.g.
  # pod-1/2 formed a 2-node non-Primary group after losing pod-0 mid-SST
  # during a TOCTOU race in parallel restart). Kill mariadbd to force a
  # container restart; galera-start.sh will re-evaluate and join the now-
  # stable Primary cluster.
  (
    set +e
    # Clear stale markers on start (see _clear_stale_markers_on_start): includes
    # any .galera-shutting-down left by a previous graceful shutdown — this is a
    # live container again.
    _clear_stale_markers_on_start
    SOCK=/run/mysqld/mysqld.sock
    SYNCED_ONCE=0
    NON_PRIMARY_COUNT=0
    NON_PRIMARY_THRESHOLD=30  # 30 × 3s = 90s
    NO_SOCKET_COUNT=0
    NO_SOCKET_THRESHOLD="${GALERA_SOCKETLESS_MARIADBD_THRESHOLD:-30}"  # 30 × 3s = 90s
    while true; do
      # The graceful-shutdown guard lives inside _restart_mariadbd_for_self_heal
      # so every self-heal call site is covered (and unit-testable): while
      # .galera-shutting-down exists the helper no-ops instead of SIGKILLing
      # mariadbd mid clean-shutdown.
      STATE=""
      CLUSTER_STATUS=""
      if [ -S "${SOCK}" ]; then
        NO_SOCKET_COUNT=0
        STATE=$(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
          -S "${SOCK}" -N -s \
          -e "SHOW STATUS LIKE 'wsrep_local_state';" 2>/dev/null \
          | awk '{print $2}')
        CLUSTER_STATUS=$(mariadb "-u${MARIADB_ROOT_USER}" "-p${MARIADB_ROOT_PASSWORD}" \
          -S "${SOCK}" -N -s \
          -e "SHOW STATUS LIKE 'wsrep_cluster_status';" 2>/dev/null \
          | awk '{print $2}')
      fi
      if [ "${STATE}" = "4" ] && [ "${CLUSTER_STATUS}" = "Primary" ]; then
        printf "primary" > "${DATA_DIR}/.galera-role.tmp" \
          && chown mysql:mysql "${DATA_DIR}/.galera-role.tmp" 2>/dev/null \
          && mv "${DATA_DIR}/.galera-role.tmp" "${DATA_DIR}/.galera-role"
        # Re-touch .galera-synced every tick (not once): the roleprobe and
        # memberJoin freshness gates reject markers older than 30s to detect a
        # dead writer, so a live-and-synced node MUST keep refreshing the
        # marker's mtime or memberJoin would wrongly report it stale and never
        # close. SYNCED_ONCE only gates the one-time "first reached Synced" log.
        touch "${DATA_DIR}/.galera-synced"
        chown mysql:mysql "${DATA_DIR}/.galera-synced" 2>/dev/null || true
        if [ "${SYNCED_ONCE}" = "0" ]; then
          SYNCED_ONCE=1
        fi
        NON_PRIMARY_COUNT=0
      else
        rm -f "${DATA_DIR}/.galera-synced" 2>/dev/null || true
        SYNCED_ONCE=0
        printf "secondary" > "${DATA_DIR}/.galera-role.tmp" \
          && chown mysql:mysql "${DATA_DIR}/.galera-role.tmp" 2>/dev/null \
          && mv "${DATA_DIR}/.galera-role.tmp" "${DATA_DIR}/.galera-role"
        if [ -S "${SOCK}" ] && [ -n "${CLUSTER_STATUS}" ] && [ "${CLUSTER_STATUS}" != "Primary" ]; then
          NON_PRIMARY_COUNT=$((NON_PRIMARY_COUNT + 1))
          if [ ${NON_PRIMARY_COUNT} -ge ${NON_PRIMARY_THRESHOLD} ]; then
            _restart_mariadbd_for_self_heal "wsrep_cluster_status=${CLUSTER_STATUS} for $((NON_PRIMARY_COUNT * 3))s"
            NON_PRIMARY_COUNT=0
          fi
        elif [ -f "${DATA_DIR}/sst_in_progress" ] || pgrep -f 'wsrep_sst_' >/dev/null 2>&1; then
          # A joiner performing SST (State Snapshot Transfer) runs mariadbd
          # WITHOUT a SQL socket until the transfer completes. A large-dataset
          # rsync/mariabackup SST can take much longer than the socketless
          # threshold, so killing mariadbd here would abort a healthy SST,
          # restart, and abort it again — permanent non-convergence, and each
          # round re-blocks the donor. The Galera SST-in-progress marker
          # (${DATA_DIR}/sst_in_progress, created by wsrep_sst_common) and a
          # live wsrep_sst_* helper process both mean SST is underway, not a
          # stall. Do not count these ticks toward the socketless kill.
          NO_SOCKET_COUNT=0
        else
          NON_PRIMARY_COUNT=0
          if pgrep -x mariadbd >/dev/null 2>&1 || pidof mariadbd >/dev/null 2>&1; then
            NO_SOCKET_COUNT=$((NO_SOCKET_COUNT + 1))
            if [ ${NO_SOCKET_COUNT} -ge ${NO_SOCKET_THRESHOLD} ]; then
              _restart_mariadbd_for_self_heal "mariadbd running without ${SOCK} for $((NO_SOCKET_COUNT * 3))s"
              NO_SOCKET_COUNT=0
            fi
          else
            NO_SOCKET_COUNT=0
          fi
        fi
      fi
      sleep 3
    done
  ) &

  if should_bootstrap; then
    echo "Starting Galera cluster bootstrap (--wsrep-new-cluster)..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}" --wsrep-new-cluster
  else
    if [ -n "${GALERA_BOOTSTRAP_DEFER_REASON:-}" ]; then
      echo "Galera bootstrap deferred: ${GALERA_BOOTSTRAP_DEFER_REASON}"
      exit 1
    fi
    local pod_index="${POD_NAME##*-}"
    if [ "$pod_index" != "0" ]; then
      _wait_for_primary_peer
    fi
    echo "Joining Galera cluster at ${cluster_address}..."
    exec docker-entrypoint.sh mariadbd "${wsrep_args[@]}"
  fi
}

# This is magic for shellspec ut framework, do not modify!
${__SOURCED__:+false} : || return 0

main "$@"
