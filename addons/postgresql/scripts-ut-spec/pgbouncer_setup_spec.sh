# shellcheck shell=bash
# shellcheck disable=SC2034

# validate_shell_type_and_version defined in shellspec/spec_helper.sh used to validate the expected shell type and version this script needs to run.
if ! validate_shell_type_and_version "bash" 4 &>/dev/null; then
  echo "pgbouncer_setup_spec.sh skip all cases because dependency bash version 4 or higher is not installed."
  exit 0
fi

source ./utils.sh

# The unit test needs to rely on the common library functions defined in kblib.
# Therefore, we first dynamically generate the required common library files from the kblib library chart.
common_library_file="./common.sh"
generate_common_library $common_library_file

Describe "PgBouncer Configuration and Startup Script Tests"

  Include ../scripts/pgbouncer-setup.sh
  Include $common_library_file

  init() {
    pgbouncer_conf_dir="./conf"
    pgbouncer_log_dir="./logs"
    pgbouncer_tmp_dir="./tmp"
    pgbouncer_conf_file="./conf/pgbouncer.ini"
    pgbouncer_user_list_file="./conf/userlist.txt"
    pgbouncer_template_conf_file="./pgbouncer.ini"
    touch $pgbouncer_template_conf_file
    echo "[pgbouncer]
          listen_addr = *
          listen_port = 6432
          unix_socket_dir = /tmp/
          unix_socket_mode = 0777
          auth_file = /opt/bitnami/pgbouncer/conf/userlist.txt
          auth_user = postgres
          auth_query = SELECT usename, passwd FROM pg_shadow WHERE usename=$1
          pidfile =/opt/bitnami/pgbouncer/tmp/pgbouncer.pid
          logfile =/opt/bitnami/pgbouncer/logs/pgbouncer.log
          auth_type = md5
          pool_mode = session
          ignore_startup_parameters = extra_float_digits
          admin_users = postgres
          ;;; [database]" > $pgbouncer_template_conf_file
  }
  BeforeAll "init"

  cleanup() {
    rm -rf ./conf ./logs ./tmp
    rm -f $common_library_file
    rm -f $pgbouncer_template_conf_file
  }
  AfterAll 'cleanup'

  Describe "build_pgbouncer_conf()"
    setup() {
      POSTGRESQL_USERNAME="testuser"
      POSTGRESQL_PASSWORD="testpassword"
      CURRENT_POD_IP="127.0.0.1"
    }
    Before 'setup'

    un_setup() {
      unset POSTGRESQL_USERNAME
      unset POSTGRESQL_PASSWORD
      unset CURRENT_POD_IP
    }
    After 'un_setup'

    It "builds the PgBouncer configuration files"
      When call build_pgbouncer_conf
      The path "$pgbouncer_conf_dir" should be directory
      The path "$pgbouncer_log_dir" should be directory
      The path "$pgbouncer_tmp_dir" should be directory
      The contents of file "$pgbouncer_user_list_file" should include "\"testuser\" \"testpassword\""
      The contents of file "$pgbouncer_conf_file" should include "listen_addr = *"
      The contents of file "$pgbouncer_conf_file" should include "listen_port = 6432"
      The contents of file "$pgbouncer_conf_file" should include "admin_users = postgres"
      The contents of file "$pgbouncer_conf_file" should include "[databases]"
      The contents of file "$pgbouncer_conf_file" should include "postgres=host=127.0.0.1 port=5432 dbname=postgres"
      The contents of file "$pgbouncer_conf_file" should include "*=host=127.0.0.1 port=5432"
      # ignore useradd commands
      The status should be failure
      The stderr should be present
    End
  End
End