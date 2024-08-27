#!/bin/bash

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
# shellcheck disable=SC2034
ut_mode="false"
test || __() {
  # when running in non-unit test mode, set the options "set -ex".
  set -ex;
}

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

  mkdir -p /opt/bitnami/pgbouncer/conf/ /opt/bitnami/pgbouncer/logs/ /opt/bitnami/pgbouncer/tmp/
  cp /home/pgbouncer/conf/pgbouncer.ini /opt/bitnami/pgbouncer/conf/
  echo "\"$POSTGRESQL_USERNAME\" \"$POSTGRESQL_PASSWORD\"" > /opt/bitnami/pgbouncer/conf/userlist.txt
  # shellcheck disable=SC2129
  echo -e "\\n[databases]" >> /opt/bitnami/pgbouncer/conf/pgbouncer.ini
  echo "postgres=host=$CURRENT_POD_IP port=5432 dbname=postgres" >> /opt/bitnami/pgbouncer/conf/pgbouncer.ini
  echo "*=host=$CURRENT_POD_IP port=5432" >> /opt/bitnami/pgbouncer/conf/pgbouncer.ini
  chmod +777 /opt/bitnami/pgbouncer/conf/pgbouncer.ini
  chmod +777 /opt/bitnami/pgbouncer/conf/userlist.txt
  useradd pgbouncer
  chown -R pgbouncer:pgbouncer /opt/bitnami/pgbouncer/conf/ /opt/bitnami/pgbouncer/logs/ /opt/bitnami/pgbouncer/tmp/
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
