# shellcheck shell=bash
# shellcheck disable=SC2034,SC2317,SC2329

Describe "PostgreSQL PgBouncer auth-file contract"
  Include ../scripts/pgbouncer-setup.sh

  setup() {
    test_dir=$(mktemp -d -t pgbouncer-authfile-XXXXXX)
    pgbouncer_template_conf_file="../config/pgbouncer-ini.tpl"
    pgbouncer_conf_dir="$test_dir/conf/"
    pgbouncer_log_dir="$test_dir/logs/"
    pgbouncer_tmp_dir="$test_dir/tmp/"
    pgbouncer_conf_file="$test_dir/conf/pgbouncer.ini"
    pgbouncer_user_list_file="$test_dir/conf/userlist.txt"
    POSTGRESQL_USERNAME=pgbouncer
    POSTGRESQL_PASSWORD='pa"ss'
    CURRENT_POD_IP=127.0.0.1
    unset POSTGRESQL_HOST POSTGRESQL_PORT
  }

  cleanup() {
    rm -rf "$test_dir"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  is_empty() {
    test -z "${1:-}"
  }

  Mock useradd
    exit 0
  End

  Mock id
    exit 0
  End

  Mock getent
    exit 0
  End

  Mock chown
    exit 0
  End

  It "doubles quotes in credentials before writing the auth file"
    When call build_pgbouncer_conf
    The status should be success
    The output should include "pgbouncer user and group are ready"
    The path "$pgbouncer_user_list_file" should be file
    The contents of file "$pgbouncer_user_list_file" should equal '"pgbouncer" "pa""ss"'
  End

  It "routes the independent component through the PostgreSQL Service"
    POSTGRESQL_HOST=sample-postgresql
    POSTGRESQL_PORT=5433
    When call build_pgbouncer_conf
    The status should be success
    The output should include "pgbouncer user and group are ready"
    The contents of file "$pgbouncer_conf_file" should include "postgres=host=sample-postgresql port=5433 dbname=postgres"
    The contents of file "$pgbouncer_conf_file" should include "*=host=sample-postgresql port=5433"
    The contents of file "$pgbouncer_conf_file" should not include "host=127.0.0.1"
  End

  It "rejects line breaks in credentials before writing the auth file"
    POSTGRESQL_PASSWORD=$(printf 'bad\nsecret')
    When call build_pgbouncer_conf
    The status should be failure
    The output should include "credentials contain an unsupported line break"
    The path "$pgbouncer_user_list_file" should not be exist
  End
End
