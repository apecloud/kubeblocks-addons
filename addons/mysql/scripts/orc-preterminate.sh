#!/bin/bash

# Logging functions
mysql_log() {
  local text="$*"; if [ "$#" -eq 0 ]; then text="$(cat)"; fi
  printf '%s\n'  "$text"
}
mysql_note() {
  mysql_log "$@"
}
mysql_warn() {
  mysql_log "$@" >&2
}
mysql_error() {
  mysql_log "$@" >&2
  exit 1
}

run_orchestrator_client() {
  local budget="${ORC_PRETERMINATE_CLIENT_TIMEOUT_SECONDS:-8}"
  timeout "${budget}s" /kubeblocks/orchestrator-client "$@"
}

forget_cluster() {
  local clusters

  if ! run_orchestrator_client -c clusters-alias >/dev/null; then
    mysql_error "Orchestrator unreachable; refusing to report cluster removal"
  fi
  if ! run_orchestrator_client -c forget-cluster -alias "${CLUSTER_NAME}"; then
    mysql_error "Failed to forget cluster alias ${CLUSTER_NAME}"
  fi

  sleep 3
  if ! clusters=$(run_orchestrator_client -c clusters-alias); then
    mysql_error "Orchestrator unreachable; cannot verify removal of ${CLUSTER_NAME}"
  fi
  if printf '%s\n' "$clusters" | awk -F, -v name="$CLUSTER_NAME" '$1 == name || $2 == name { found=1 } END { exit !found }'; then
    mysql_error "Cluster ${CLUSTER_NAME} still exists in Orchestrator"
  fi
  mysql_note "Cluster ${CLUSTER_NAME} successfully removed from Orchestrator"
}

${__SOURCED__:+false} : || return 0
forget_cluster
