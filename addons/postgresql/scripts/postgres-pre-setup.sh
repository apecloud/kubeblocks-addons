#!/bin/bash

postgres_template_conf_file="/home/postgres/conf/postgresql.conf"
postgres_conf_dir="/home/postgres/pgdata/conf/"
postgres_conf_file="/home/postgres/pgdata/conf/postgresql.conf"
postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"
postgres_walg_dir="/home/postgres/pgdata/wal-g"

build_real_postgres_conf() {
  mkdir -p "$postgres_conf_dir" || return $?

  # Copy the template config file first
  cp "$postgres_template_conf_file" "$postgres_conf_dir" || return $?

  # Set permissions
  chmod 755 "$postgres_conf_dir" || return $?
  chmod 664 "$postgres_conf_file" || return $?
}

init_postgres_log() {
  mkdir -p "$postgres_log_dir" || return $?
  chmod -R 777 "$postgres_log_dir" || return $?
  touch "$postgres_scripts_log_file" || return $?
  chmod 666 "$postgres_scripts_log_file" || return $?
}

copy_necessary_binaries() {
  mkdir -p "$postgres_walg_dir" || return $?
  cp /spilo-init/bin/wal-g "${postgres_walg_dir}/wal-g" || return $?
}

main() {
  build_real_postgres_conf || return $?
  init_postgres_log || return $?
  copy_necessary_binaries || return $?
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

main
