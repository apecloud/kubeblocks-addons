# shellcheck shell=sh
# shellcheck disable=SC2034,SC2317,SC2329

Describe "PgBouncer setup contract"
  Include ../scripts/pgbouncer-setup.sh

  setup() {
    test_dir=$(mktemp -d -t pgbouncer-setup-XXXXXX)
    mkdir -p "$test_dir/conf" "$test_dir/tmp"
    sed -n '/^\[pgbouncer\]/,$p' ../config/pgbouncer-ini.tpl > "$test_dir/pgbouncer.ini.tpl"
    pgbouncer_template_conf_file="$test_dir/pgbouncer.ini.tpl"
    pgbouncer_conf_dir="$test_dir/conf"
    pgbouncer_conf_file="$test_dir/conf/pgbouncer.ini"
    pgbouncer_user_list_file="$test_dir/conf/userlist.txt"
    POSTGRESQL_USERNAME=postgres
    POSTGRESQL_PASSWORD='pa"ss'
    PGBOUNCER_ADMIN_USERNAME=pgbouncer
    PGBOUNCER_ADMIN_PASSWORD='admin"secret'
    POSTGRESQL_HOST=sample-postgresql
    POSTGRESQL_PORT=5432
    CURRENT_POD_NAME=sample-pgbouncer-0
    PGBOUNCER_COMPONENT_NAME=sample-pgbouncer
    pgbouncer_peers_file="$test_dir/peers.ini"
    printf '[peers]\n1 = host=sample-pgbouncer-0.sample-pgbouncer-headless port=6432\n' > "$pgbouncer_peers_file"
    chmod 0555 "$pgbouncer_peers_file"
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

  enable_backend_tls() {
    sed 's/server_tls_sslmode = disable/server_tls_sslmode = verify-full/' \
      "$pgbouncer_template_conf_file" > "$test_dir/tls.ini"
    mv "$test_dir/tls.ini" "$pgbouncer_template_conf_file"
    build_pgbouncer_conf
  }

  BeforeEach 'setup'
  AfterEach 'cleanup'

  It "doubles quotes in credentials before writing the auth file"
    When call build_pgbouncer_conf
    The status should be success
    The path "$pgbouncer_user_list_file" should be file
    The contents of file "$pgbouncer_user_list_file" should include '"postgres" "pa""ss"'
    The contents of file "$pgbouncer_user_list_file" should include '"pgbouncer" "admin""secret"'
  End

  It "keeps the peer identity stable for a non-contiguous ordinal above the replica limit"
    CURRENT_POD_NAME=sample-pgbouncer-100
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "peer_id = 101"
    The contents of file "$pgbouncer_conf_file" should include "%include $pgbouncer_peers_file"
    The contents of file "$pgbouncer_conf_dir/peers.applied" should include "[peers]"
  End

  It "rejects a peer ID outside the protocol range"
    CURRENT_POD_NAME=sample-pgbouncer-65535
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "outside 0..65534"
  End

  It "rejects custom instance names rather than reusing another peer identity"
    CURRENT_POD_NAME=sample-pgbouncer-other-0
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "requires a default instance name"
  End

  It "loads the documented pool defaults from the managed configuration"
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "%include $pgbouncer_template_conf_file"
    The contents of file "$pgbouncer_template_conf_file" should include "pool_mode = session"
    The contents of file "$pgbouncer_template_conf_file" should include "max_client_conn = 500"
    The contents of file "$pgbouncer_template_conf_file" should include "default_pool_size = 20"
    The contents of file "$pgbouncer_template_conf_file" should include "min_pool_size = 5"
    The contents of file "$pgbouncer_template_conf_file" should include "reserve_pool_size = 5"
    The contents of file "$pgbouncer_template_conf_file" should include "max_db_connections = 80"
    The contents of file "$pgbouncer_template_conf_file" should include "max_user_connections = 80"
  End

  It "preserves user-provided pool limits without automatic recalculation"
    When call customize_pool_limits
    The status should be success
    The contents of file "$pgbouncer_template_conf_file" should include "max_client_conn = 1200"
    The contents of file "$pgbouncer_template_conf_file" should include "default_pool_size = 30"
    The contents of file "$pgbouncer_template_conf_file" should include "max_db_connections = 60"
    The contents of file "$pgbouncer_template_conf_file" should include "max_user_connections = 40"
  End

  It "keeps backend TLS disabled by default"
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_template_conf_file" should include "server_tls_sslmode = disable"
    The contents of file "$pgbouncer_template_conf_file" should include "server_tls_ca_file = /etc/pgbouncer/tls/ca.pem"
  End

  It "preserves managed backend TLS settings and PostgreSQL Service routing"
    When call enable_backend_tls
    The status should be success
    The contents of file "$pgbouncer_template_conf_file" should include "server_tls_sslmode = verify-full"
    The contents of file "$pgbouncer_template_conf_file" should include "client_tls_sslmode = disable"
    The contents of file "$pgbouncer_conf_file" should include "%include $pgbouncer_template_conf_file"
    The contents of file "$pgbouncer_conf_file" should include "host=sample-postgresql"
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

  It "references and extends a read-only managed configuration"
    chmod 0444 "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be success
    The contents of file "$pgbouncer_conf_file" should include "%include $pgbouncer_template_conf_file"
    The contents of file "$pgbouncer_conf_file" should include "[databases]"
  End

  It "rejects line breaks in credentials before writing files"
    POSTGRESQL_PASSWORD=$(printf 'bad\nsecret')
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "credentials contain an unsupported line break"
    The path "$pgbouncer_user_list_file" should not be exist
  End

  It "requires the independent management credential"
    unset PGBOUNCER_ADMIN_PASSWORD
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "management credentials are required"
    The path "$pgbouncer_user_list_file" should not be exist
  End

  It "rejects line breaks in management credentials"
    PGBOUNCER_ADMIN_PASSWORD=$(printf 'bad\nsecret')
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "credentials contain an unsupported line break"
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

  It "fails when the managed configuration is unavailable"
    rm -f "$pgbouncer_template_conf_file"
    When call build_pgbouncer_conf
    The status should be failure
    The stderr should include "configuration is not readable"
  End
End
