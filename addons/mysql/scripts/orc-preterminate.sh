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

# Forget cluster
if /kubeblocks/orchestrator-client -c forget-cluster -i "${KB_AGENT_POD_NAME}" 2>&1; then
  mysql_note "Forget cluster command executed"
else
  mysql_note "Forget cluster command failed, continuing anyway"
fi

if /kubeblocks/orchestrator-client -c forget-cluster -alias "${CLUSTER_NAME}" 2>&1; then
  mysql_note "Forget cluster command executed"
else
  mysql_note "Forget cluster command failed, continuing anyway"
fi


sleep 3

# Check if cluster still exists
cluster_name=$(/kubeblocks/orchestrator-client -c which-cluster -i "${KB_AGENT_POD_NAME}" 2>/dev/null || echo "")
if [ -z "$cluster_name" ]; then
  mysql_note "Cluster successfully forgotten from Orchestrator"
  exit 0
fi

mysql_error "Cluster still exists in Orchestrator: ${cluster_name}"
