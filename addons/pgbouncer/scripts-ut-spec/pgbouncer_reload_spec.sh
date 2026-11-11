# shellcheck shell=sh

Describe "PgBouncer reload"
  setup() {
    tmp_dir=$(mktemp -d)
    export PATH="$tmp_dir:$PATH"
    export PGBOUNCER_ADMIN_USERNAME=pgbouncer PGBOUNCER_ADMIN_PASSWORD=test-only CURRENT_POD_IP=127.0.0.2
    export TEST_LOG="$tmp_dir/call" TEST_EXIT=0
    cat > "$tmp_dir/psql" <<'SCRIPT'
#!/bin/sh
printf '%s\n' "$@" > "$TEST_LOG"
[ "$PGPASSWORD" = test-only ] && [ "$PGCONNECT_TIMEOUT" = 3 ] || exit 91
exit "$TEST_EXIT"
SCRIPT
    cat > "$tmp_dir/timeout" <<'SCRIPT'
#!/bin/sh
[ "$1 $2 $3" = '-s KILL 5' ] || exit 92
shift 3
exec "$@"
SCRIPT
    chmod +x "$tmp_dir/psql" "$tmp_dir/timeout"
  }
  cleanup() { rm -rf "$tmp_dir"; }
  Before 'setup'
  After 'cleanup'

  It "reloads the local management database and asks psql to preserve SQL errors"
    When run sh ../scripts/pgbouncer-reload.sh
    The status should be success
    The contents of file "$TEST_LOG" should include '--host=127.0.0.2'
    The contents of file "$TEST_LOG" should include '--dbname=pgbouncer'
    The contents of file "$TEST_LOG" should include '--username=pgbouncer'
    The contents of file "$TEST_LOG" should include '--set=ON_ERROR_STOP=1'
    The contents of file "$TEST_LOG" should include '--command=RELOAD'
  End

  It "propagates a failed reload"
    export TEST_EXIT=7
    When run sh ../scripts/pgbouncer-reload.sh
    The status should eq 7
  End

  It "fails before connecting when management credentials are missing"
    unset PGBOUNCER_ADMIN_PASSWORD
    When run sh ../scripts/pgbouncer-reload.sh
    The status should be failure
    The stderr should include 'PGBOUNCER_ADMIN_PASSWORD'
    The path "$TEST_LOG" should not be exist
  End
End
