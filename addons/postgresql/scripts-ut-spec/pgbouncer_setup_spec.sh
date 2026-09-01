# shellcheck shell=sh
# shellcheck disable=SC2034,SC2317,SC2329

Describe "PostgreSQL PgBouncer setup contract"
  Include ../scripts/pgbouncer-setup.sh

  setup() {
    test_dir=$(mktemp -d -t pgbouncer-setup-XXXXXX)
    mkdir -p "$test_dir/conf" "$test_dir/tmp"
    sed -n '/^\[pgbouncer\]/,$p' ../config/pgbouncer-ini.tpl > "$test_dir/pgbouncer.ini.tpl"
    pgbouncer_template_conf_file="$test_dir/pgbouncer.ini.tpl"
    pgbouncer_conf_dir="$test_dir/conf"
    pgbouncer_conf_file="$test_dir/conf/pgbouncer.ini"
    pgbouncer_user_list_file="$test_dir/conf/userlist.txt"
    POSTGRESQL_USERNAME=pgbouncer
    POSTGRESQL_PASSWORD='pa"ss'
    POSTGRESQL_HOST=sample-postgresql
    POSTGRESQL_PORT=5432
  }

  cleanup() {
    rm -rf "$test_dir"
  }

  customize_pool_limits() {
    sed \
      -e 's/max_client_conn = 500/max_client_conn = 1200/' \
      -e 's/default_pool_size = 20/default_pool_size = 30/' \
      -e 's/max_db_connections = 80/max_db_connections = 60/' \
      -e 's/max_user_connections = 80/max_user_connections = 40/' \
      "$pgbouncer_template_conf_file" > "$test_dir/custom.ini"
    mv "$test_dir/custom.ini" "$pgbouncer_template_conf_file"
    build_pgbouncer_conf
  }

  rebuild_for_new_backend() {
    build_pgbouncer_conf || return 1
    POSTGRESQL_HOST=replaced-postgresql
    build_pgbouncer_conf
  }

  inject_protected_setting() {
    sed '/^max_client_conn = 500$/a\
auth_type = trust' "$pgbouncer_template_conf_file" > "$test_dir/injected.ini"
    mv "$test_dir/injected.ini" "$pgbouncer_template_conf_file"
    build_pgbouncer_conf
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "doubles quotes in credentials before writing the auth file"
    When call build_pgbouncer_conf
    The status should be success
    The path "$pgbouncer_user_list_file" should be file
    The contents of file "$pgbouncer_user_list_file" should equal '"pgbouncer" "pa""ss"'
  End

  It "keeps the documented static pool defaults"
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "pool_mode = session"
    The contents of file "$pgbouncer_conf_file" should include "max_client_conn = 500"
    The contents of file "$pgbouncer_conf_file" should include "default_pool_size = 20"
    The contents of file "$pgbouncer_conf_file" should include "min_pool_size = 5"
    The contents of file "$pgbouncer_conf_file" should include "reserve_pool_size = 5"
    The contents of file "$pgbouncer_conf_file" should include "max_db_connections = 80"
    The contents of file "$pgbouncer_conf_file" should include "max_user_connections = 80"
  End

  It "preserves user-provided pool limits without automatic recalculation"
    When call customize_pool_limits
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "max_client_conn = 1200"
    The contents of file "$pgbouncer_conf_file" should include "default_pool_size = 30"
    The contents of file "$pgbouncer_conf_file" should include "max_db_connections = 60"
    The contents of file "$pgbouncer_conf_file" should include "max_user_connections = 40"
  End

  It "rejects a newline injection that overrides a protected setting"
    When call inject_protected_setting
    The status should be failure
    The stderr should include "duplicate setting: auth_type"
    The path "$pgbouncer_conf_file" should not be exist
  End

  It "rejects a custom template that replaces the protected auth type"
    sed 's/auth_type = md5/auth_type = trust/' \
      "$pgbouncer_template_conf_file" > "$test_dir/injected.ini"
    mv "$test_dir/injected.ini" "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "managed setting cannot be overridden: auth_type"
  End

  It "rejects extra tokens on a managed setting"
    sed 's/listen_addr = \*/listen_addr = * extra/' \
      "$pgbouncer_template_conf_file" > "$test_dir/injected.ini"
    mv "$test_dir/injected.ini" "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "managed setting cannot be overridden: listen_addr"
  End

  It "rejects non-canonical and out-of-range pool values"
    sed 's/max_client_conn = 500/max_client_conn = 1000000/' \
      "$pgbouncer_template_conf_file" > "$test_dir/invalid.ini"
    mv "$test_dir/invalid.ini" "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "outside the supported range"
  End

  It "rejects an unsupported pool mode"
    sed 's/pool_mode = session/pool_mode = unsafe/' \
      "$pgbouncer_template_conf_file" > "$test_dir/invalid.ini"
    mv "$test_dir/invalid.ini" "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "pool_mode must be session, transaction, or statement"
  End

  It "rejects a negative pool value"
    sed 's/max_db_connections = 80/max_db_connections = -1/' \
      "$pgbouncer_template_conf_file" > "$test_dir/invalid.ini"
    mv "$test_dir/invalid.ini" "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "must be a canonical decimal integer"
  End

  It "routes the PgBouncer component through the PostgreSQL Service"
    POSTGRESQL_PORT=5433
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "postgres=host=sample-postgresql port=5433 dbname=postgres"
    The contents of file "$pgbouncer_conf_file" should include "*=host=sample-postgresql port=5433"
  End

  It "atomically replaces an existing generated configuration"
    When call rebuild_for_new_backend
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "host=replaced-postgresql"
    The contents of file "$pgbouncer_conf_file" should not include "host=sample-postgresql"
  End

  It "copies and extends a read-only ConfigMap template"
    chmod 0444 "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "[databases]"
  End

  It "rejects line breaks in credentials before writing files"
    POSTGRESQL_PASSWORD=$(printf 'bad\nsecret')
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "credentials contain an unsupported line break"
    The path "$pgbouncer_user_list_file" should not be exist
  End

  It "fails when the required PostgreSQL Service host is missing"
    unset POSTGRESQL_HOST
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "POSTGRESQL_HOST or POSTGRESQL_PORT is not set"
  End

  It "rejects an invalid PostgreSQL Service port"
    POSTGRESQL_PORT=70000
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "outside 1..65535"
  End
End
