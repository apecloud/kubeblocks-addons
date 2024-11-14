#!/usr/bin/env bash
#
# startup.sh
# Start YASDB database instance if not already running

# This is magic for shellspec ut framework. "test" is a `test [expression]` well known as a shell command.
# Normally test without [expression] returns false. It means that __() { :; }
# function is defined if this script runs directly.
#
# shellspec overrides the test command and returns true *once*. It means that
# __() function defined internally by shellspec is called.
#
# In other words. If not in test mode, __ is just a comment. If test mode, __
# is a interception point.
# you should set ut_mode="true" when you want to run the script in shellspec file.
#
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  set -exuo pipefail;
}

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
  START_LOG_FILE="$YASDB_DATA/log/start.log"

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

# Start YASDB process
start_yasdb_process() {
  rm -rf "${START_LOG_FILE}"
  "${YASDB_BIN}" open -D "$YASDB_DATA" >"$START_LOG_FILE" 2>&1 &

  local i=0
  while ((i < 5)); do
    sleep 2
    if grep -q "Instance started" "$START_LOG_FILE"; then
      echo "process started!"
      return 0
    fi
    ((i++))
  done

  echo "start process failed. read $START_LOG_FILE"
  cat "$START_LOG_FILE"
  return 1
}

main() {
  load_environment

  if is_yasdb_running; then
    echo "yasdb is already running"
    sleep infinity
  fi

  if start_yasdb_process; then
    sleep infinity
  else
    exit 1
  fi
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main "$@"