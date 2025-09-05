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
  
  # Create shared directories for inter-container usage
  shared_dir="/shared"
  mkdir -p "$shared_dir/bin" "$shared_dir/scripts"
  chmod -R 755 "$shared_dir"

  echo "Copying essential binaries to shared volume..."
  # Copy specific binaries needed by the main container
  for binary in pg_waldump pg_controldata pg_resetwal pg_rewind; do
    binary_path=$(command -v "$binary" 2>/dev/null)
    if [ -n "$binary_path" ]; then
      echo "Found $binary at $binary_path, copying to shared bin directory"
      cp "$binary_path" "$shared_dir/bin/"
      chmod 755 "$shared_dir/bin/$binary"
    else
      # Try to find in standard PostgreSQL installation directories
      for pg_bin_dir in /usr/lib/postgresql/*/bin /usr/pgsql-*/bin /opt/postgresql/*/bin /usr/local/bin; do
        if [ -f "$pg_bin_dir/$binary" ]; then
          echo "Found $binary at $pg_bin_dir/$binary, copying to shared bin directory"
          cp "$pg_bin_dir/$binary" "$shared_dir/bin/"
          chmod 755 "$shared_dir/bin/$binary"
          break
        fi
      done
    fi
  done

  # Copy scripts if available
  echo "Copying scripts to shared volume..."
  for scripts_dir in /scripts /opt/scripts /usr/local/scripts; do
    if [ -d "$scripts_dir" ]; then
      echo "Copying scripts from $scripts_dir to shared scripts directory"
      cp -r "$scripts_dir"/* "$shared_dir/scripts/" 2>/dev/null || true
    fi
  done
  
  chmod -R 755 "$shared_dir/scripts" 2>/dev/null || true
  
  # List all shared files for verification
  echo "Files available in shared bin directory:"
  ls -la "$shared_dir/bin/"
  
  echo "Files available in shared scripts directory:"
  ls -la "$shared_dir/scripts/" 2>/dev/null || true
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