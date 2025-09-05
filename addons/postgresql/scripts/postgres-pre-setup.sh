#!/bin/bash

postgres_template_conf_file="/home/postgres/conf/postgresql.conf"
postgres_conf_dir="/home/postgres/pgdata/conf/"
postgres_conf_file="/home/postgres/pgdata/conf/postgresql.conf"
postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
postgres_walg_dir="/home/postgres/pgdata/wal-g"

build_real_postgres_conf() {
  mkdir -p "$postgres_conf_dir"
  chmod -R 777 "$postgres_conf_dir"
  cp "$postgres_template_conf_file" "$postgres_conf_dir"
  chmod 777 "$postgres_conf_file"
}

init_postgres_log() {
  mkdir -p "$postgres_log_dir"
  chmod -R 777 "$postgres_log_dir"
  touch "$postgres_scripts_log_file"
  chmod 666 "$postgres_scripts_log_file"
}

copy_necessary_binaries() {
  # Create original wal-g directory
  mkdir -p ${postgres_walg_dir}
  if [ -f /spilo/bin/wal-g ]; then
    cp /spilo/bin/wal-g ${postgres_walg_dir}/wal-g
  fi

  # Copy files from spilo to shared volume for other containers
  if [ -d "/spilo" ]; then
    echo "Copying files from /spilo directory to shared volume (excluding /spilo/bin)..."
    
    # Create shared directory if it doesn't exist (should be auto-mounted)
    mkdir -p /shared
    
    # Copy all directories and files from /spilo except the bin directory
    for item in /spilo/*; do
      item_name=$(basename "$item")
      if [ "$item_name" != "bin" ]; then
        echo "Copying $item to /shared/"
        cp -a "$item" /shared/ 2>/dev/null || echo "Failed to copy $item"
      fi
    done
    
    # List copied files for verification
    echo "Files available in shared directory:"
    ls -la /shared/ 2>/dev/null || true
  else
    echo "Warning: /spilo directory not found, skipping copy operation"
  fi
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