#!/bin/bash
set -Eeuo pipefail

DATA_DIR="${DATA_DIR:-/var/lib/rabbitmq}"
TARGET_POD_NAME="${DP_TARGET_POD_NAME:?DP_TARGET_POD_NAME is required}"
ARCHIVE_NAME="${TARGET_POD_NAME}.tar.zst"
MARKER_BASE_PATH="$(dirname "${DP_BACKUP_BASE_PATH:?DP_BACKUP_BASE_PATH is required}")/.rabbitmq-physical-br/${DP_BACKUP_NAME:?DP_BACKUP_NAME is required}"
MARKER_TIMEOUT_SECONDS="${RABBITMQ_BACKUP_BARRIER_TIMEOUT_SECONDS:-600}"
APP_STOPPED=false
CLUSTER_NODES=()

mark_failed() {
  local exit_code=$?
  if [ "${APP_STOPPED}" = "true" ]; then
    if [ "${#CLUSTER_NODES[@]}" -gt 0 ]; then
      for node in "${CLUSTER_NODES[@]}"; do
        rabbitmqctl --longnames -n "${node}" start_app || true
      done
    else
      rabbitmqctl --longnames -n "${RABBITMQ_NODENAME:?RABBITMQ_NODENAME is required}" start_app || true
    fi
  fi
  if [ "${exit_code}" -ne 0 ]; then
    echo "ERROR: backup failed with exit code ${exit_code}" >&2
    touch "${DP_BACKUP_INFO_FILE:?DP_BACKUP_INFO_FILE is required}.exit"
  fi
  exit "${exit_code}"
}
trap mark_failed EXIT

[ -n "${DP_DATASAFED_BIN_PATH:-}" ] && export PATH="${PATH}:${DP_DATASAFED_BIN_PATH}"
export DATASAFED_BACKEND_BASE_PATH="${DP_BACKUP_BASE_PATH}"

datasafed_at() {
  local base_path="$1"
  shift
  DATASAFED_BACKEND_BASE_PATH="${base_path}" datasafed "$@"
}

write_marker() {
  local phase="$1"
  printf '%s\n' "${TARGET_POD_NAME}" | datasafed_at "${MARKER_BASE_PATH}" push - "${phase}/${TARGET_POD_NAME}"
}

marker_count() {
  local phase="$1"
  datasafed_at "${MARKER_BASE_PATH}" list "${phase}" 2>/dev/null | grep -c "${phase}/" || true
}

wait_for_markers() {
  local phase="$1"
  local expected="$2"
  local elapsed=0
  local count=0
  while [ "${elapsed}" -lt "${MARKER_TIMEOUT_SECONDS}" ]; do
    count="$(marker_count "${phase}")"
    if [ "${count}" -ge "${expected}" ]; then
      echo "INFO: observed ${count}/${expected} RabbitMQ ${phase} barrier markers"
      return 0
    fi
    sleep 5
    elapsed=$((elapsed + 5))
  done
  echo "ERROR: timed out waiting for RabbitMQ ${phase} barrier markers; observed ${count}/${expected}" >&2
  return 1
}

if [ ! -d "${DATA_DIR}" ]; then
  echo "ERROR: DATA_DIR ${DATA_DIR} does not exist" >&2
  exit 1
fi

cookie_file="${DATA_DIR}/.erlang.cookie"
if [ -r "${cookie_file}" ]; then
  export RABBITMQ_ERLANG_COOKIE
  RABBITMQ_ERLANG_COOKIE="$(cat "${cookie_file}")"
fi

discover_cluster_nodes() {
  rabbitmqctl --longnames -n "${RABBITMQ_NODENAME:?RABBITMQ_NODENAME is required}" cluster_status | awk '
    /^Disk Nodes/ { in_disk = 1; next }
    /^Running Nodes|^Versions|^Alarms|^Network Partitions|^Listeners|^Feature flags/ { in_disk = 0 }
    in_disk {
      for (i = 1; i <= NF; i++) {
        if ($i ~ /^rabbit@/) {
          gsub(/[,"]/, "", $i)
          print $i
        }
      }
    }
  ' | sort -u
}

stop_node_app() {
  local node="$1"
  local output=""
  if output="$(rabbitmqctl --longnames -n "${node}" stop_app 2>&1)"; then
    echo "INFO: stopped RabbitMQ application on ${node}"
    return 0
  fi
  if printf '%s\n' "${output}" | grep -Eiq 'not running|already.*stopped|is stopped'; then
    echo "INFO: RabbitMQ application on ${node} was already stopped"
    return 0
  fi
  printf '%s\n' "${output}" >&2
  echo "ERROR: failed to stop RabbitMQ application on ${node}" >&2
  return 1
}

start_node_app() {
  local node="$1"
  rabbitmqctl --longnames -n "${node}" start_app || true
}

echo "INFO: RabbitMQ backup target pod=${TARGET_POD_NAME} node=${RABBITMQ_NODENAME}"
rabbitmqctl --longnames -n "${RABBITMQ_NODENAME:?RABBITMQ_NODENAME is required}" await_startup
while IFS= read -r node; do
  [ -n "${node}" ] && CLUSTER_NODES+=("${node}")
done < <(discover_cluster_nodes)
if [ "${#CLUSTER_NODES[@]}" -eq 0 ]; then
  echo "ERROR: could not discover RabbitMQ cluster nodes before physical backup" >&2
  exit 1
fi
echo "INFO: stopping RabbitMQ applications on discovered nodes: ${CLUSTER_NODES[*]}"
APP_STOPPED=true
for node in "${CLUSTER_NODES[@]}"; do
  stop_node_app "${node}"
done
write_marker stopped
wait_for_markers stopped "${#CLUSTER_NODES[@]}"

echo "INFO: archiving RabbitMQ data directory ${DATA_DIR} for target ${TARGET_POD_NAME}"
cd "${DATA_DIR}"
tar \
  --exclude='./logs' \
  --exclude='./logs/*' \
  --exclude='./.kb-data-protection' \
  -cvf - ./ | datasafed push -z zstd-fastest - "${ARCHIVE_NAME}"
write_marker archived
wait_for_markers archived "${#CLUSTER_NODES[@]}"

echo "INFO: restarting RabbitMQ applications after all target archives completed"
for node in "${CLUSTER_NODES[@]}"; do
  start_node_app "${node}"
done
APP_STOPPED=false

TOTAL_SIZE="$(datasafed stat "${ARCHIVE_NAME}" | awk '/TotalSize/ {print $2; exit}')"
TOTAL_SIZE="${TOTAL_SIZE:-0}"
printf '{"totalSize":"%s","extras":[{"name":"targetPod","value":"%s"}]}\n' \
  "${TOTAL_SIZE}" "${TARGET_POD_NAME}" > "${DP_BACKUP_INFO_FILE}" && sync
echo "INFO: backup archive ${ARCHIVE_NAME} saved successfully"
