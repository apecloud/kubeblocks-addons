#!/bin/bash

postgres_template_conf_file="/home/postgres/conf/postgresql.conf"
postgres_conf_dir="/home/postgres/pgdata/conf/"
postgres_conf_file="/home/postgres/pgdata/conf/postgresql.conf"
postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
postgres_walg_dir="/home/postgres/pgdata/wal-g"
spilo_scripts_dir="/spilo"

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

prepare_shared_volume() {
  # Create original wal-g directory
  mkdir -p ${postgres_walg_dir}
  
  # Copy wal-g binary if available
  if [ -f "${spilo_scripts_dir}/bin/wal-g" ]; then
    echo "Copying wal-g from ${spilo_scripts_dir}/bin to ${postgres_walg_dir}"
    cp "${spilo_scripts_dir}/bin/wal-g" "${postgres_walg_dir}/wal-g"
  else
    echo "Warning: wal-g binary not found at ${spilo_scripts_dir}/bin/wal-g"
  fi
  
  # Log available files in spilo directory for reference
  echo "Files available in ${spilo_scripts_dir} directory:"
  ls -la ${spilo_scripts_dir} 2>/dev/null || echo "No files found in ${spilo_scripts_dir}"
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
prepare_shared_volume