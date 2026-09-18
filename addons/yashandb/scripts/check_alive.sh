#!/usr/bin/env bash

# Check YASDB database readiness with a lightweight SQL command.

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

# 2026-06-02 Reason: provide a minimal SQL-backed readiness contract; Purpose: mark the pod ready only when YASDB can answer the user-approved instance status query.
WORK_DIR=${WORK_DIR:-/home/yashan}
YASDB_PASSWORD="${YASDB_PASSWORD:-yasdb_123}"
YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"

source_env_files() {
  # shellcheck disable=SC1090
  source "${YASDB_TEMP_FILE}"

  YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
  YASDB_HOME_BIN_PATH="${YASDB_HOME}/bin"
  YASQL_BIN="${YASDB_HOME_BIN_PATH}/yasql"

  # shellcheck disable=SC1090
  source "${YASDB_ENV_FILE}"
}

check_alive() {
  source_env_files
  # 2026-06-18 Reason: restore proof showed MOUNTED can satisfy a zero-exit SQL call but still reject business queries; Purpose: mark readiness only when the instance is OPEN.
  "${YASQL_BIN}" sys/"$YASDB_PASSWORD" -c "select status from v\$instance" | grep -q OPEN
}

main() {
  check_alive
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main "$@"
