#!/usr/bin/env bash

# Perform a YASDB database switchover by delegating to the database command.

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

# 2026-06-02 Reason: provide the approved phase-A switchover script without wiring native KubeBlocks HA; Purpose: keep switchover behavior limited to the user-confirmed YASDB SQL command.
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

switchover_database() {
  source_env_files

  # 2026-06-02 Reason: YashanDB documents switchover as a standby-side operation; Purpose: prevent KubeBlocks from reporting success when the action is invoked on the current primary.
  if [ "${KB_SWITCHOVER_ROLE:-}" != "" ] && [ "${KB_SWITCHOVER_ROLE}" != "secondary" ]; then
    echo "YASDB switchover must be executed on a secondary pod, current role is ${KB_SWITCHOVER_ROLE}." >&2
    return 1
  fi

  "${YASQL_BIN}" sys/"$YASDB_PASSWORD" -c "alter database switchover"
}

main() {
  switchover_database
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main "$@"
