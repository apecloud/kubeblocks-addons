#!/bin/bash

pgbouncer_template_conf_file="/home/pgbouncer/conf/pgbouncer.ini"
pgbouncer_conf_dir="/opt/bitnami/pgbouncer/conf/"
pgbouncer_log_dir="/opt/bitnami/pgbouncer/logs/"
pgbouncer_tmp_dir="/opt/bitnami/pgbouncer/tmp/"
pgbouncer_conf_file="/opt/bitnami/pgbouncer/conf/pgbouncer.ini"
pgbouncer_user_list_file="/opt/bitnami/pgbouncer/conf/userlist.txt"

load_common_library() {
  # the common.sh scripts is mounted to the same path which is defined in the cmpd.spec.scripts
  common_library_file="/kb-scripts/common.sh"
  # shellcheck disable=SC1090
  source "${common_library_file}"
}

build_pgbouncer_conf() {
  if is_empty "$POSTGRESQL_USERNAME" || is_empty "$POSTGRESQL_PASSWORD" || is_empty "$CURRENT_POD_IP"; then
    echo "POSTGRESQL_USERNAME, POSTGRESQL_PASSWORD or CURRENT_POD_IP is not set. Exiting..."
    exit 1
  fi

  mkdir -p $pgbouncer_conf_dir $pgbouncer_log_dir $pgbouncer_tmp_dir
  cp $pgbouncer_template_conf_file $pgbouncer_conf_dir
  echo "\"$POSTGRESQL_USERNAME\" \"$POSTGRESQL_PASSWORD\"" > $pgbouncer_user_list_file
  # shellcheck disable=SC2129
  echo -e "\\n[databases]" >> $pgbouncer_conf_file
  echo "postgres=host=$CURRENT_POD_IP port=5432 dbname=postgres" >> $pgbouncer_conf_file
  echo "*=host=$CURRENT_POD_IP port=5432" >> $pgbouncer_conf_file
  chmod 777 $pgbouncer_conf_file
  chmod 777 $pgbouncer_user_list_file
  useradd pgbouncer
  chown -R pgbouncer:pgbouncer $pgbouncer_conf_dir $pgbouncer_log_dir $pgbouncer_tmp_dir
}

start_pgbouncer() {
  /opt/bitnami/scripts/pgbouncer/run.sh
}

# This is magic for shellspec ut framework.
# Sometime, functions are defined in a single shell script.
# You will want to test it. but you do not want to run the script.
# When included from shellspec, __SOURCED__ variable defined and script
# end here. The script path is assigned to the __SOURCED__ variable.
${__SOURCED__:+false} : || return 0

# main
load_common_library
build_pgbouncer_conf
start_pgbouncer
