#!/usr/bin/env bash

# Check YASDB database role and map it to KubeBlocks replica roles.

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

# 2026-06-02 Reason: expose YashanDB primary/standby state to KubeBlocks roleProbe; Purpose: map V$DATABASE.DATABASE_ROLE to KubeBlocks primary/secondary labels.
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

map_database_role() {
  local role_output="${1:-}"

  if echo "$role_output" | grep -Eq '\bPRIMARY\b'; then
    echo -n "primary"
    return 0
  fi

  if echo "$role_output" | grep -Eq '\bSTANDBY\b'; then
    echo -n "secondary"
    return 0
  fi

  echo "unknown YASDB database role" >&2
  return 1
}

check_role() {
  local role_output

  source_env_files
  role_output=$("${YASQL_BIN}" sys/"$YASDB_PASSWORD" -c "select database_role from v\$database")
  map_database_role "$role_output"
}

main() {
  check_role
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main "$@"
