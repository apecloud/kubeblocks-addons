# shellcheck shell=sh
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
    POSTGRESQL_HOST=sample-postgresql
    POSTGRESQL_PORT=5432
    CURRENT_POD_IP=127.0.0.1
  }

  cleanup() {
    rm -rf "$test_dir"
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "doubles quotes in credentials before writing the auth file"
    When call build_pgbouncer_conf
    The status should be success
    The path "$pgbouncer_user_list_file" should be file
    The contents of file "$pgbouncer_user_list_file" should equal '"pgbouncer" "pa""ss"'
  End

  It "routes the independent component through the PostgreSQL Service"
    POSTGRESQL_HOST=sample-postgresql
    POSTGRESQL_PORT=5433
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "postgres=host=sample-postgresql port=5433 dbname=postgres"
    The contents of file "$pgbouncer_conf_file" should include "*=host=sample-postgresql port=5433"
    The contents of file "$pgbouncer_conf_file" should not include "host=127.0.0.1"
  End

  It "copies and extends a read-only ConfigMap template"
    projected_template="$test_dir/projected-pgbouncer.ini"
    cp "$pgbouncer_template_conf_file" "$projected_template"
    chmod 0444 "$projected_template"
    pgbouncer_template_conf_file="$projected_template"
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "[databases]"
    The contents of file "$pgbouncer_conf_file" should include "postgres=host=sample-postgresql port=5432 dbname=postgres"
  End

  It "rejects line breaks in credentials before writing the auth file"
    POSTGRESQL_PASSWORD=$(printf 'bad\nsecret')
    When call build_pgbouncer_conf
    The status should be failure
    The output should include "credentials contain an unsupported line break"
    The path "$pgbouncer_user_list_file" should not be exist
  End

  It "fails when the required PostgreSQL Service host is missing"
    unset POSTGRESQL_HOST
    When call build_pgbouncer_conf
    The status should be failure
    The output should include "POSTGRESQL_HOST or POSTGRESQL_PORT is not set"
    The path "$pgbouncer_user_list_file" should not be exist
  End

  It "fails when the required PostgreSQL Service port is missing"
    unset POSTGRESQL_PORT
    When call build_pgbouncer_conf
    The status should be failure
    The output should include "POSTGRESQL_HOST or POSTGRESQL_PORT is not set"
    The path "$pgbouncer_user_list_file" should not be exist
  End
End
