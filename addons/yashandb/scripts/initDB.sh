#!/usr/bin/env bash

# Initialize YASDB database
# This script handles installation and configuration of YASDB database

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
YASDB_PASSWORD="yasdb_123"

# Config file paths
YASDB_TEMP_FILE="${YASDB_MOUNT_HOME}/.temp.ini"
YASDB_INSTALL_FILE="${YASDB_MOUNT_HOME}/install.ini"
INSTALL_INI_FILE="${YASDB_INSTALL_FILE}"
START_LOG_FILE="${YASDB_DATA}/log/start.log"

# Load environment files
source_env_files() {
  # shellcheck disable=SC1090
  source "${YASDB_TEMP_FILE}"
  
  YASDB_ENV_FILE="${YASDB_HOME}/conf/yasdb.bashrc"
  YASDB_HOME_BIN_PATH="${YASDB_HOME}/bin"
  YASDB_BIN="${YASDB_HOME_BIN_PATH}/yasdb"
  YASQL_BIN="${YASDB_HOME_BIN_PATH}/yasql"
  YASPWD_BIN="${YASDB_HOME_BIN_PATH}/yaspwd"
  
  # shellcheck disable=SC1090
  source "${YASDB_ENV_FILE}"
}

# Configure installation files
setup_install_files() {
  local e_i s_i n_i
  e_i=$(sed -n '$=' "$INSTALL_INI_FILE")
  s_i=$(sed -n -e '/\<instance\>/=' "$INSTALL_INI_FILE")
  n_i=$((s_i + 1))
  
  sed -n "${n_i},${e_i} p" "$INSTALL_INI_FILE" >>"$YASDB_DATA"/config/yasdb.ini
}

# Setup password file
setup_password() {
  if [ -f "$YASDB_HOME/admin/yasdb.pwd" ]; then
    rm -f "$YASDB_HOME"/admin/yasdb.pwd
  fi
  
  "$YASPWD_BIN" file="$YASDB_HOME"/admin/yasdb.pwd password="$YASDB_PASSWORD"
  cp "$YASDB_HOME"/admin/yasdb.pwd "$YASDB_DATA"/instance/yasdb.pwd
}

# Generate redo file configuration
generate_redo_config() {
  local redo_file="("
  for ((i = 0; i < REDO_FILE_NUM; i++)); do
    if [ "$i" -eq "$((REDO_FILE_NUM - 1))" ]; then
      redo_file=${redo_file}"'redo${i}'"" size $REDO_FILE_SIZE)"
    else
      redo_file=${redo_file}"'redo${i}'"" size $REDO_FILE_SIZE,"
    fi
  done
  echo "$redo_file"
}

# Start YASDB process
start_yasdb_process() {
  rm -rf "${START_LOG_FILE}"
  "${YASDB_BIN}" nomount -D "$YASDB_DATA" >"$START_LOG_FILE" 2>&1 &
  
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

# Create and initialize database
create_database() {
  local redo_file
  redo_file=$(generate_redo_config)
  
  "${YASQL_BIN}" sys/"$YASDB_PASSWORD" >>"$START_LOG_FILE" <<EOF
create database yasdb CHARACTER SET $NLS_CHARACTERSET logfile $redo_file;
exit;
EOF
  
  local i=0
  while ((i < 60)); do
    sleep 1
    if [ "$("$YASQL_BIN" sys/"$YASDB_PASSWORD" -c "select open_mode from v\$database" | grep -c READ_WRITE)" -eq 1 ]; then
      echo "Database open succeed!"
      return 0
    fi
    ((i++))
  done
  
  echo "Failed! please check logfile $START_LOG_FILE."
  return 1
}

# Install sample schema if requested
install_sample_schema() {
  if [[ "${INSTALL_SIMPLE_SCHEMA_SALES,,}" == "y" ]]; then
    "${YASQL_BIN}" sys/"$YASDB_PASSWORD" -f "$YASDB_HOME"/admin/simple_schema/sales.sql >>"$START_LOG_FILE"
  fi
}

main() {
  source_env_files
  setup_install_files
  setup_password
  start_yasdb_process || exit 1
  create_database || exit 1
  install_sample_schema

  sleep infinity
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main "$@"