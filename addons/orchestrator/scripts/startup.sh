#!/usr/bin/env bash
set -Eeuo pipefail

#######################################
# Signal handling
#######################################
ORC_PID=""

shutdown() {
  echo "Received termination signal. Shutting down orchestrator..."
  if [[ -n "${ORC_PID}" ]] && kill -0 "${ORC_PID}" 2>/dev/null; then
    kill -TERM "${ORC_PID}"
    wait "${ORC_PID}" || true
  fi
}

trap shutdown TERM INT EXIT

#######################################
# Defaults & required envs
#######################################
WORKDIR="${WORKDIR:-/opt/orchestrator}"
ORC_RAFT_ENABLED="${ORC_RAFT_ENABLED:-true}"
ORC_BACKEND_DB="${ORC_BACKEND_DB:-sqlite}"

META_MYSQL_PORT="${META_MYSQL_PORT:-3306}"
META_MYSQL_ENDPOINT="${META_MYSQL_ENDPOINT:-}"
ORC_META_DATABASE="${ORC_META_DATABASE:-orchestrator}"

: "${CURRENT_POD_NAME:?CURRENT_POD_NAME is required}"
: "${COMPONENT_NAME:?COMPONENT_NAME is required}"
: "${CLUSTER_NAMESPACE:?CLUSTER_NAMESPACE is required}"
if [[ "${ORC_RAFT_ENABLED}" == "true" ]]; then
  : "${ORC_PER_POD_SVC:?ORC_PER_POD_SVC is required if ORC_RAFT_ENABLED is true}"
fi

META_MYSQL_HOST="${META_MYSQL_ENDPOINT%%:*}"

#######################################
# Directories
#######################################
mkdir -p "${WORKDIR}/raft" "${WORKDIR}/sqlite"

POD_SUFFIX="${CURRENT_POD_NAME##*-}"
ORC_ADVERTISE_SVC="${COMPONENT_NAME}-advertise-${POD_SUFFIX}.${CLUSTER_NAMESPACE}.svc"
SUBDOMAIN="${COMPONENT_NAME}-headless.${CLUSTER_NAMESPACE}.svc"

if [[ "${ORC_RAFT_ENABLED}" == "true" ]]; then
  PEERS=""
  IFS=',' read -ra REPLICA_ARRAY <<< "${ORC_PER_POD_SVC}"
  for replica in "${REPLICA_ARRAY[@]}"; do
    host="${replica}.${CLUSTER_NAMESPACE}.svc"
    PEERS+=",\"${host}\""
  done
  PEERS="${PEERS#,}"
  ORC_PEERS="${PEERS}"
  ORC_POD_NAME="${CURRENT_POD_NAME}.${SUBDOMAIN}"
else
  ORC_PEERS=""
  ORC_POD_NAME=""
fi

#######################################
# Render config (single sed pass)
#######################################
CONFIG_FILE="${WORKDIR}/orchestrator.conf.json"

sed \
  -e "s|\${ORC_BACKEND_DB}|${ORC_BACKEND_DB}|g" \
  -e "s|\${ORC_WORKDIR}|${WORKDIR}|g" \
  -e "s|\${META_MYSQL_ENDPOINT}|${META_MYSQL_HOST}|g" \
  -e "s|\${META_MYSQL_PORT}|${META_MYSQL_PORT}|g" \
  -e "s|\${ORC_META_DATABASE}|${ORC_META_DATABASE}|g" \
  -e "s|\${ORC_RAFT_ENABLED}|${ORC_RAFT_ENABLED}|g" \
  -e "s|\${ORC_PEERS}|${ORC_PEERS}|g" \
  -e "s|\${ORC_POD_NAME}|${ORC_POD_NAME}|g" \
  -e "s|\${ORC_ADVERTISE_SVC}|${ORC_ADVERTISE_SVC}|g" \
  /configs/orchestrator.tpl > "${CONFIG_FILE}"

#######################################
# Start orchestrator
#######################################
/usr/local/orchestrator/orchestrator \
  -config "${CONFIG_FILE}" \
  http &

ORC_PID=$!
wait "${ORC_PID}"
