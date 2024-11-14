#!/usr/bin/env bash
#
# Stop YASDB database instance if running

set -exuo pipefail

# Default configurations
WORK_DIR=${WORK_DIR:-/home/yashan}

# Config file paths
YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"

# Load environment files
load_environment() {
  # shellcheck disable=SC1090
  source "${YASDB_TEMP_FILE}"

  YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
  YASDB_BIN="${YASDB_HOME}/bin/yasdb"

  # shellcheck disable=SC1090
  source "${YASDB_ENV_FILE}"
}

# Check if YASDB process is running
is_yasdb_running() {
  local process_count
  # shellcheck disable=SC2009
  process_count=$(ps -aux | grep -w "$YASDB_BIN" | grep -w "$YASDB_DATA" | grep -v -w grep | wc -l)
  [ "$process_count" -gt 0 ]
}

# Get YASDB process ID
get_yasdb_pid() {
  # shellcheck disable=SC2009
  ps -aux | grep -w "$YASDB_BIN" | grep -w "$YASDB_DATA" | grep -v -w grep | awk '{print $2}'
}

# Wait for YASDB to stop
wait_yasdb_stop() {
  local i=0
  while ((i < 5)); do
    sleep 1
    if ! is_yasdb_running; then
      return 0
    fi
    ((i++))
  done
  return 1
}

# Stop YASDB process
stop_yasdb() {
  local pid

  if ! is_yasdb_running; then
    echo "yasdb is already stopped"
    return 0
  fi

  pid=$(get_yasdb_pid)
  kill -15 "$pid"

  if wait_yasdb_stop; then
    echo "Succeed!"
    return 0
  else
    echo "Failed!"
    return 1
  fi
}

main() {
  load_environment
  stop_yasdb
}

main "$@"