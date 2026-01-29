#!/bin/bash

postgres_template_conf_file="/home/postgres/conf/postgresql.conf"
postgres_conf_dir="/home/postgres/pgdata/conf/"
postgres_conf_file="/home/postgres/pgdata/conf/postgresql.conf"
postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
postgres_walg_dir="/home/postgres/pgdata/wal-g"

build_real_postgres_conf() {
  mkdir -p "$postgres_conf_dir"
  
  # Copy the template config file first
  cp "$postgres_template_conf_file" "$postgres_conf_dir"
  
  # Try to set ownership using username first
  # Note: This may fail in init containers that don't have postgres user
  if chown -R postgres:postgres "$postgres_conf_dir" 2>/dev/null; then
    echo "Set ownership using username 'postgres:postgres'"
  else
    # Fallback to numeric UID/GID
    # Get postgres user UID and GID using id command
    POSTGRES_UID=$(id -u postgres 2>/dev/null)
    POSTGRES_GID=$(id -g postgres 2>/dev/null)
    
    # Fallback to common defaults if id command fails
    POSTGRES_UID=${POSTGRES_UID:-101}
    POSTGRES_GID=${POSTGRES_GID:-103}
    
    echo "Set ownership using numeric UID:GID = ${POSTGRES_UID}:${POSTGRES_GID}"
    chown -R ${POSTGRES_UID}:${POSTGRES_GID} "$postgres_conf_dir"
  fi
  
  # Set directory permissions
  chmod 755 "$postgres_conf_dir"
  
  # Set config file permissions - use 666 to allow Patroni to modify it
  chmod 666 "$postgres_conf_file"
}

init_postgres_log() {
  mkdir -p "$postgres_log_dir"
  chmod -R 777 "$postgres_log_dir"
  touch "$postgres_scripts_log_file"
  chmod 666 "$postgres_scripts_log_file"
}

copy_necessary_binaries() {
  mkdir -p "$postgres_walg_dir"
  cp /spilo-init/bin/wal-g ${postgres_walg_dir}/wal-g
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
build_real_postgres_conf
init_postgres_log
copy_necessary_binaries
