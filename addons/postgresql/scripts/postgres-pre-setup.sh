#!/bin/bash

postgres_template_conf_file="/home/postgres/conf/postgresql.conf"
postgres_conf_dir="/home/postgres/pgdata/conf/"
postgres_conf_file="/home/postgres/pgdata/conf/postgresql.conf"
postgres_log_dir="/home/postgres/pgdata/logs/"
postgres_scripts_log_file="${postgres_log_dir}/scripts.log"

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

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
build_real_postgres_conf
init_postgres_log
